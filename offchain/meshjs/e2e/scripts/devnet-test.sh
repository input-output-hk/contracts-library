#!/usr/bin/env bash
# Ephemeral Yaci devnet lifecycle for the MeshJS e2e tests.
#
# Starts a throwaway devnet before each test file, waits until its
# Blockfrost-compatible API is serving blocks, runs the file against it, then
# tears it down before moving to the next file. The chain is kept across files
# (Yaci 0.12 restarts the existing cluster); each suite creates its own wallets
# and contracts, so no state leaks between them.
#
# Yaci DevKit 0.12 runs a Yano-based bootstrap in companion mode: the node
# catches up to wall-clock time from a Yano backfill, so no genesis or clock
# overrides are needed (the 0.10.6 `shiftStartTimeBehind` workaround and
# `config/node.properties` are gone).
#
# The CLI keeps its components and clusters under `yaci.cli.home` (default
# `~/.yaci-cli`). This script isolates it per pinned version under
# `<repo>/.yaci/<version>`, so a global install of another version can neither
# be reused nor broken by a version mismatch. The home must stay under the
# 108-byte limit of the node's Unix socket path, hence the repo root and not
# this package directory.
#
# Degrades gracefully when yaci-devkit is not installed: the suite then runs
# with no devnet and skips itself, so local runs stay green. Set
# REQUIRE_DEVNET=1 (as CI does) to fail instead of silently skipping.
#
# Test files without the `.e2e.` marker (e.g. event_triggered.builders.test.ts)
# are offline suites: they need no devnet, so a full run executes them first,
# before the per-file devnet lifecycle starts. A single-file run skips them.
#
# Invoked via `npm run test:devnet`. Yaci DevKit supports Linux x64 and
# macOS arm64 (not Windows).
set -u

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"

shopt -s globstar 2>/dev/null \
  || echo "⚠ bash lacks globstar; nested test files under test/ are not discovered"

API_URL="http://localhost:8080/api/v1/"
ADMIN_URL="http://localhost:10000"
LOG=".yaci-devnet.log"
REPORT=".vitest-report.json"
WAIT_SECONDS="${YACI_WAIT_SECONDS:-240}"

# Every e2e file under test/ is picked up by glob, so a new test file runs
# here without anyone remembering to extend a hand-maintained list. Pass a
# file path to run a single file instead.
shopt -s nullglob
TEST_FILES=(test/**/*.e2e.test.ts)
shopt -u nullglob
if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "✗ no e2e test files found (test/**/*.e2e.test.ts)"
  exit 1
fi

# Version-isolated Yaci home. The pinned e2e devDependency decides the version
# segment, so bumping it starts from a clean component cache.
YACI_VERSION=""
if [ -f node_modules/@bloxbean/yaci-devkit/package.json ]; then
  YACI_VERSION="$(node -p "require('./node_modules/@bloxbean/yaci-devkit/package.json').version" 2>/dev/null || true)"
fi
YACI_HOME="${YACI_HOME:-$ROOT/.yaci/${YACI_VERSION:-dev}}"

# The node binds its Unix socket under `<home>/local-clusters/<cluster>/node/`,
# and `sun_path` holds 108 bytes including the terminator.
SOCKET_PATH="$YACI_HOME/local-clusters/default/node/node.sock"
if [ ${#SOCKET_PATH} -gt 107 ]; then
  echo "✗ YACI_HOME is too long for the node's Unix socket (${#SOCKET_PATH} > 107 bytes):"
  echo "  $SOCKET_PATH"
  echo "  Set YACI_HOME to a shorter path and retry."
  exit 1
fi

YACI_BIN=""
if [ -x "node_modules/.bin/yaci-devkit" ]; then
  YACI_BIN="$PWD/node_modules/.bin/yaci-devkit"
  echo "• Using pinned yaci-devkit ${YACI_VERSION:-?}: $YACI_BIN"
  echo "• Isolated Yaci home: $YACI_HOME"
elif command -v yaci-devkit >/dev/null 2>&1; then
  YACI_BIN="$(command -v yaci-devkit)"
  echo "• Using a global yaci-devkit: $YACI_BIN"
  echo "  The pinned version is an e2e devDependency; run \`npm ci\` in offchain/meshjs/e2e."
  echo "• Isolated Yaci home: $YACI_HOME"
fi

if [ -z "$YACI_BIN" ]; then
  echo "• yaci-devkit not installed. Running the suite without a devnet (it will skip)."
  echo "  Run \`npm ci\` in offchain/meshjs/e2e for the full e2e run."
  if [ "${REQUIRE_DEVNET:-0}" = "1" ]; then
    echo "✗ REQUIRE_DEVNET=1: refusing to run an e2e suite that would skip everything."
    exit 1
  fi
  exec npm test
fi

CURRENT_DEVNET_PID=""

show_devnet_errors() {
  echo "----- $LOG (last 60 lines) -----"
  tail -n 60 "$LOG" | sed 's/^/  /' || true
  echo "----- error lines -----"
  grep -iE 'error|exception|not found|failed|refused|ENAMETOOLONG' "$LOG" \
    | tail -n 20 | sed 's/^/  /' || true
}

stop_devnet() {
  if [ -n "$CURRENT_DEVNET_PID" ]; then
    kill "$CURRENT_DEVNET_PID" >/dev/null 2>&1 || true
    pkill -TERM -P "$CURRENT_DEVNET_PID" >/dev/null 2>&1 || true
  fi
  # The launcher and its components (cardano-node, Yano, Yaci Store, Ogmios)
  # carry the isolated home in their command line or their install path.
  pkill -TERM -f "$YACI_HOME" >/dev/null 2>&1 || true
  sleep 1
  pkill -KILL -f "$YACI_HOME" >/dev/null 2>&1 || true
  CURRENT_DEVNET_PID=""
}
teardown() {
  echo "Tearing down devnet ..."
  stop_devnet
}
trap 'teardown; exit 1' INT TERM

# Is the devnet's Blockfrost-compatible API answering?
devnet_api_up() {
  node -e "
    fetch('${API_URL}blocks/latest', { signal: AbortSignal.timeout(3000) })
      .then((res) => process.exit(res.ok ? 0 : 1))
      .catch(() => process.exit(1));
  " >/dev/null 2>&1
}

run_file() {
  local TEST_FILE="$1"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $TEST_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  mkdir -p "$YACI_HOME"
  nohup "$YACI_BIN" -Dyaci.cli.home="$YACI_HOME" up --enable-yaci-store \
    >"$LOG" 2>&1 &
  CURRENT_DEVNET_PID=$!

  echo "Waiting for the devnet API (up to ${WAIT_SECONDS}s) ..."
  local waited=0
  while ! devnet_api_up; do
    if ! kill -0 "$CURRENT_DEVNET_PID" >/dev/null 2>&1 \
      && ! pgrep -f "$YACI_HOME" >/dev/null 2>&1; then
      echo "✗ The devnet process exited before its API came up."
      show_devnet_errors
      stop_devnet
      return 1
    fi
    if [ "$waited" -ge "$WAIT_SECONDS" ]; then
      echo "✗ The devnet API did not come up in ${WAIT_SECONDS}s."
      show_devnet_errors
      stop_devnet
      return 1
    fi
    sleep 3
    waited=$((waited + 3))
  done

  echo "Devnet is up. Running e2e tests ..."
  INDEXER_URL="$API_URL" YACI_ADMIN_URL="$ADMIN_URL" npx vitest run "$TEST_FILE" --reporter=verbose --reporter=json --outputFile.json="$REPORT"
  local TEST_EXIT=$?

  # A green vitest exit can still mean zero tests ran: the suite skips itself
  # when the devnet probe fails. Fail unless at least one test executed.
  if [ $TEST_EXIT -eq 0 ]; then
    node -e '
      const report = require(process.argv[1]);
      if ((report.numPassedTests ?? 0) === 0) {
        console.error(
          `✗ no tests executed (${report.numPendingTests ?? 0} skipped): the devnet suite did not run.`,
        );
        process.exit(1);
      }
    ' "$PWD/$REPORT" || TEST_EXIT=1
  fi
  rm -f "$REPORT"

  echo "Tearing down devnet ..."
  stop_devnet
  sleep 2

  return $TEST_EXIT
}

HAD_FILE_ARG=0
if [[ $# -gt 0 && "$1" != -* ]]; then
  HAD_FILE_ARG=1
  TEST_FILES=("$1")
  shift
fi

# Offline suites (test files without the .e2e. marker) run once, without a
# devnet, in a full run; a single-file run is targeted debugging and skips
# them. Like the devnet glob above, a new offline test file is picked up
# automatically.
if [ "$HAD_FILE_ARG" -eq 0 ]; then
  shopt -s nullglob
  OFFLINE_FILES=()
  for file in test/**/*.test.ts; do
    case "$file" in *.e2e.test.ts) ;; *) OFFLINE_FILES+=("$file") ;; esac
  done
  shopt -u nullglob
  if [ ${#OFFLINE_FILES[@]} -gt 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  offline suites (no devnet)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    npx vitest run "${OFFLINE_FILES[@]}" --reporter=verbose || exit 1
  else
    echo "• no offline test files found (test/*.test.ts without .e2e.)"
  fi
fi

FAILED=0
for file in "${TEST_FILES[@]}"; do
  run_file "$file" || FAILED=1
done

exit $FAILED

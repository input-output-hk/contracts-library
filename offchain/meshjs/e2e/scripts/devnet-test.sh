# Ephemeral Yaci devnet lifecycle for the MeshJS e2e tests.
#
# Starts a fresh throwaway devnet before each test file, waits until its
# Blockfrost-compatible API is serving blocks, runs the file against it, then
# tear down before moving to the next file. Each file gets a completely clean
# chain, so test files never pollute each other's state (e.g. stake credential
# registrations).
#
# Degrades gracefully when yaci-devkit is not installed: the suite then runs
# with no devnet and skips itself, so this stays green anywhere.
#
# Invoked via `npm run test:devnet`. Yaci DevKit supports Linux x64 and
# macOS arm64 (not Windows).
set -u

API_URL="http://localhost:8080/api/v1/"
ADMIN_URL="http://localhost:10000"
LOG=".yaci-devnet.log"

TEST_FILES=(
  "test/vesting.e2e.test.ts"
  "test/prediction-market.e2e.test.ts"
)

if ! command -v yaci-devkit >/dev/null 2>&1; then
  echo "• yaci-devkit not installed. Running the suite without a devnet (it will skip)."
  echo "  Install it for the full e2e run: npm install -g @bloxbean/yaci-devkit"
  exec npm test
fi

CURRENT_DEVNET_PID=""
teardown() {
  echo "Tearing down devnet ..."
  if [ -n "$CURRENT_DEVNET_PID" ]; then kill "$CURRENT_DEVNET_PID" >/dev/null 2>&1 || true; fi
  pkill -f "$HOME/.yaci-cli/" >/dev/null 2>&1 || true
}
trap 'teardown; exit 1' INT TERM

run_file() {
  local TEST_FILE="$1"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $TEST_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  nohup yaci-devkit up --enable-yaci-store >"$LOG" 2>&1 &
  CURRENT_DEVNET_PID=$!

  echo "Waiting for the devnet API (up to 150s) ..."
  node -e "
  const url = '${API_URL}blocks/latest';
  const deadline = Date.now() + 150000;
  const probe = async () => {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
      if (res.ok) process.exit(0);
    } catch {}
    if (Date.now() > deadline) { console.error('timed out waiting for the devnet API'); process.exit(1); }
    setTimeout(probe, 3000);
  };
  probe();
  " || { echo "Devnet did not become ready."; return 1; }

  echo "Devnet is up. Running e2e tests ..."
  INDEXER_URL="$API_URL" YACI_ADMIN_URL="$ADMIN_URL" npx vitest run "$TEST_FILE"
  local TEST_EXIT=$?

  echo "Tearing down devnet ..."
  if [ -n "$CURRENT_DEVNET_PID" ]; then kill "$CURRENT_DEVNET_PID" >/dev/null 2>&1 || true; fi
  pkill -f "$HOME/.yaci-cli/" >/dev/null 2>&1 || true
  CURRENT_DEVNET_PID=""
  sleep 2

  return $TEST_EXIT
}

if [[ $# -gt 0 && "$1" != -* ]]; then
  TEST_FILES=("$1")
  shift
fi


FAILED=0
for file in "${TEST_FILES[@]}"; do
  run_file "$file" || FAILED=1
done

exit $FAILED

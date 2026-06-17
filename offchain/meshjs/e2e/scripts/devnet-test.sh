# Ephemeral Yaci devnet lifecycle for the MeshJS vesting e2e tests.
#
# Starts a throwaway devnet, waits until its Blockfrost-compatible API is
# serving blocks, runs the e2e suite against it, then ALWAYS tears it down.
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

if ! command -v yaci-devkit >/dev/null 2>&1; then
  echo "• yaci-devkit not installed. Running the suite without a devnet (it will skip)."
  echo "  Install it for the full e2e run: npm install -g @bloxbean/yaci-devkit"
  exec npm test
fi

DEVNET_PID=""
teardown() {
  status=$?
  echo "Tearing down the ephemeral devnet ..."
  if [ -n "$DEVNET_PID" ]; then kill "$DEVNET_PID" >/dev/null 2>&1 || true; fi
  pkill -f "$HOME/.yaci-cli/" >/dev/null 2>&1 || true
  exit "$status"
}
trap teardown EXIT INT TERM

echo "Starting ephemeral Yaci devnet (logs: $LOG) ..."
nohup yaci-devkit up --enable-yaci-store >"$LOG" 2>&1 &
DEVNET_PID=$!

echo "Waiting for the devnet API to serve blocks (up to 150s) ..."
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
" || { echo "✗ Devnet did not become ready. Recent log:"; tail -n 30 "$LOG" 2>/dev/null || true; exit 1; }

echo "Devnet is up. Running e2e suite ..."
INDEXER_URL="$API_URL" YACI_ADMIN_URL="$ADMIN_URL" npm test

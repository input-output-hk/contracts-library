#!/usr/bin/env bash
set -euo pipefail

upv_formal=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
upv_temp=$(mktemp -d)
trap 'rm -rf -- "$upv_temp"' EXIT
upv_bin="$upv_temp/bin with spaces"
upv_caller="$upv_temp/project with spaces"
mkdir -p -- "$upv_temp/tools" "$upv_caller"
cat > "$upv_temp/tools/lake" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == build ]]; then
  exit "${UPV_TEST_BUILD_EXIT:-0}"
fi
pwd -P
printf '%s\n' "$@"
MOCK
chmod +x "$upv_temp/tools/lake"
export PATH="$upv_temp/tools:$PATH"

bash "$upv_formal/install.sh" --bin-dir "$upv_bin" >/dev/null
test "$(readlink -f -- "$upv_bin/plutus-upv")" = "$upv_formal/plutus-upv"
bash "$upv_formal/install.sh" --bin-dir "$upv_bin" >/dev/null

mapfile -t upv_actual < <(cd -- "$upv_caller" && "$upv_bin/plutus-upv" run)
test "${upv_actual[0]}" = "$upv_formal"
test "${upv_actual[1]}" = exe
test "${upv_actual[2]}" = plutus-upv
test "${upv_actual[3]}" = run
test "${upv_actual[4]}" = "$upv_caller/plutus.json"
test "${#upv_actual[@]}" = 5

mapfile -t upv_actual < <(cd -- "$upv_caller" && "$upv_bin/plutus-upv" run --checks-file 'my checks.json')
test "${upv_actual[4]}" = "$upv_caller/plutus.json"
test "${upv_actual[5]}" = --checks-file
test "${upv_actual[6]}" = "$upv_caller/my checks.json"

mapfile -t upv_actual < <(cd -- "$upv_caller" && "$upv_bin/plutus-upv" run 'other blueprint.json' --validator vault --check UP-001)
test "${upv_actual[4]}" = "$upv_caller/other blueprint.json"
test "${upv_actual[6]}" = vault
test "${upv_actual[8]}" = UP-001

mapfile -t upv_actual < <(cd -- "$upv_caller" && "$upv_bin/plutus-upv" run --help)
test "${upv_actual[4]}" = --help
test "${#upv_actual[@]}" = 5

mkdir -p -- "$upv_temp/occupied"
printf 'keep this file\n' > "$upv_temp/occupied/plutus-upv"
if bash "$upv_formal/install.sh" --bin-dir "$upv_temp/occupied" >/dev/null 2>&1; then
  printf 'Installer replaced an occupied target\n' >&2
  exit 1
fi
test "$(cat "$upv_temp/occupied/plutus-upv")" = 'keep this file'

if UPV_TEST_BUILD_EXIT=9 bash "$upv_formal/install.sh" --bin-dir "$upv_temp/failed" >/dev/null 2>&1; then
  printf 'Installer accepted a failed build\n' >&2
  exit 1
fi
test ! -e "$upv_temp/failed/plutus-upv"
test ! -L "$upv_temp/failed/plutus-upv"
printf 'Installer and launcher checks passed.\n'

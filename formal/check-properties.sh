#!/usr/bin/env bash
# Usage, from formal/: scripts/check-properties.sh <Module> [schema]   e.g. Universal, Vesting.Linear
set -euo pipefail
mod="Formal.$1"; props="Formal/${1//.//}/properties.json"; tmp=$(mktemp --suffix=.lean); trap 'rm -f "$tmp"' EXIT
lake build "$mod" 2>&1 | awk -f scripts/annotate-blaster-logs.awk
npx --yes ajv-cli@5 validate --spec=draft2020 -s "${2:-Formal/Universal/schema.json}" -d "$props"
{ echo "import $mod"; node -p "require('./$props').flatMap(p => p.theorems).map(t => '#print axioms ' + t).join('\n')"; } > "$tmp"
out=$(lake env lean "$tmp" 2>&1) || true; echo "$out"
! grep -qE 'error:|sorryAx' <<< "$out"

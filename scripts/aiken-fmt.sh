#!/usr/bin/env bash
# Formats staged Aiken (.ak) files with `aiken fmt`.
#
# Invoked by lint-staged from the repository root; receives staged file paths
# relative to the root. Aiken requires running from a project directory that
# contains an `aiken.toml`, and the repository holds two such projects
# (onchain/ and offchain/meshjs/e2e/fixtures/aiken/), so files are grouped by
# their project and formatted with paths relative to it.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"

project_for() {
  local dir
  dir="$(dirname "$(realpath "$1")")"
  while [ "$dir" != "$root" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/aiken.toml" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "error: no aiken.toml found for $1" >&2
  return 1
}

declare -A project_files
for f in "$@"; do
  f="$(realpath --relative-to="$root" "$f")"
  proj="$(project_for "$f")"
  project_files["$proj"]+=" $f"
done

for proj in "${!project_files[@]}"; do
  read -r -a files <<< "${project_files[$proj]}"
  rel=()
  for f in "${files[@]}"; do
    rel+=("$(realpath --relative-to="$proj" "$root/$f")")
  done
  (
    cd "$proj"
    aiken fmt "${rel[@]}"
  )
done

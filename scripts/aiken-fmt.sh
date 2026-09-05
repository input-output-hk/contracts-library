#!/usr/bin/env bash
# Formats staged Aiken (.ak) files with `aiken fmt`.
#
# Invoked by lint-staged from the repository root; receives staged file paths
# relative to the root. Aiken requires running from a project directory that
# contains an `aiken.toml`, and the repository holds two such projects
# (onchain/ and offchain/meshjs/e2e/fixtures/aiken/), so files are grouped by
# their project and formatted with paths relative to it.
#
# Portable to macOS stock bash 3.2: no associative arrays (bash >= 4) and no
# GNU realpath --relative-to; paths are handled with parameter expansion.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"

# Print the nearest enclosing project dir (relative to the repo root) for a
# root-relative file path; error if no aiken.toml applies.
project_for() {
  local dir
  dir="$(dirname "$1")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/aiken.toml" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "error: no aiken.toml found for $1" >&2
  return 1
}

# Normalize a staged path to root-relative (strip a leading "./" and, if
# lint-staged passed an absolute path, the "$root/" prefix).
normalize() {
  local f="${1#./}"
  case "$f" in
    "$root"/*) f="${f#"$root"/}" ;;
  esac
  printf '%s\n' "$f"
}

[ $# -eq 0 ] && exit 0

# Group files per project: parallel indexed arrays (bash 3.2-safe) with
# newline-joined file lists, so paths containing spaces survive.
projs=()
groups=()
for arg in "$@"; do
  f="$(normalize "$arg")"
  proj="$(project_for "$f")"
  grouped=""
  for i in "${!projs[@]}"; do
    if [ "${projs[$i]}" = "$proj" ]; then
      groups[$i]="${groups[$i]}"$'\n'"$f"
      grouped=1
      break
    fi
  done
  [ -n "$grouped" ] || { projs+=("$proj"); groups+=("$f"); }
done

for i in "${!projs[@]}"; do
  proj="${projs[$i]}"
  rel=()
  while IFS= read -r f; do
    rel+=("${f#"$proj"/}") # file path relative to its project
  done <<< "${groups[$i]}"
  (
    cd "$proj"
    aiken fmt "${rel[@]}"
  )
done

#!/usr/bin/env bash
set -euo pipefail

upv_root=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
upv_bin_dir="$HOME/.local/bin"
case ${1:-} in
  '')
    if (( $# != 0 )); then
      printf 'Unexpected empty argument\n' >&2
      exit 2
    fi ;;
  --help|-h)
    printf 'Usage: %s [--bin-dir DIRECTORY]\nBuild Plutus UPV and install its checkout-backed launcher (default: ~/.local/bin).\n' "$0"
    exit 0 ;;
  --bin-dir)
    if (( $# != 2 )) || [[ -z $2 ]]; then
      printf 'Expected --bin-dir DIRECTORY\n' >&2
      exit 2
    fi
    upv_bin_dir=$2 ;;
  *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

for upv_tool in lake z3 timeout mktemp date readlink; do
  if ! command -v "$upv_tool" >/dev/null 2>&1; then
    printf 'Missing required tool: %s. See Workflow/Docs/USER-GUIDE.md.\n' "$upv_tool" >&2
    exit 1
  fi
done

upv_target="$upv_bin_dir/plutus-upv"
upv_launcher="$upv_root/plutus-upv"
upv_existing=false
if [[ -e $upv_target || -L $upv_target ]]; then
  if [[ -L $upv_target ]] && [[ $(readlink -f -- "$upv_target") == "$upv_launcher" ]]; then
    upv_existing=true
  else
    printf 'Refusing to replace existing path: %s\nChoose another --bin-dir or resolve that path first.\n' "$upv_target" >&2
    exit 1
  fi
fi

(cd -- "$upv_root" && lake build plutus-upv)
mkdir -p -- "$upv_bin_dir"
upv_bin_dir=$(cd -- "$upv_bin_dir" && pwd -P)
upv_target="$upv_bin_dir/plutus-upv"
if [[ $upv_existing == false ]]; then
  ln -s -- "$upv_launcher" "$upv_target"
fi
printf 'Installed: %s\nUses checkout: %s\nRun from a directory containing plutus.json: plutus-upv run\n' "$upv_target" "$upv_root"
case ":$PATH:" in
  *":$upv_bin_dir:"*) ;;
  *) printf 'Add this directory to your shell PATH:\n  export PATH=%q:$PATH\n' "$upv_bin_dir" ;;
esac

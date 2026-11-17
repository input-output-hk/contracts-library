#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
records="$(node "$fixture_dir/verify-artifacts.mjs")"
while IFS=$'\t' read -r model expected input_hex; do
  actual="$(printf '%s' "$input_hex" | xxd -r -p | b2sum -l 224 | cut -d ' ' -f 1)"
  test "$actual" = "$expected"
  printf '%s: verified source, embedded CBOR, V3 hash, and 28-byte own identity\n' "$model"
done <<< "$records"

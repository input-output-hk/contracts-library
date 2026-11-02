#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$fixture_dir/../../.." && pwd)"

# Check the source files used to compile the synthetic control.
(
  cd "$fixture_dir"
  jq -r '.sourceSha256 | to_entries[] | "\(.value)  \(.key)"' artifact.json |
    sha256sum --check --strict
  jq -r '"\(.blueprintSha256)  \(.blueprint)"' artifact.json |
    sha256sum --check --strict
)

control_blueprint="$fixture_dir/Inputs/control.json"
jq -e '.preamble.compiler.version == "v1.1.21+42babe5" and
  .preamble.plutusVersion == "v3"' "$control_blueprint" >/dev/null
control_code="$(jq -er '.validators[] | select(.title == "stake_control.stake_control.spend") | .compiledCode' "$control_blueprint")"
frozen_control="$(sed -n 's/.*singleCborEncodedScriptFromHexM "\([0-9a-f]*\)".*/\1/p' "$fixture_dir/Control.lean")"
test "$control_code" = "$frozen_control"
control_hash="$(jq -er '.validators[] | select(.title == "stake_control.stake_control.spend") | .hash' "$control_blueprint")"
test "$control_hash" = "$(jq -er '.scriptHashHex' "$fixture_dir/artifact.json")"
test "$control_hash" = "$(sed -n 's/^def controlScriptHashHex : String := "\([0-9a-f]*\)"/\1/p' "$fixture_dir/Control.lean")"
control_sha256="$(printf '%s' "$control_code" | xxd -r -p | sha256sum | cut -d ' ' -f1)"
test "$control_sha256" = "$(jq -er '.compiledCodeSha256' "$fixture_dir/artifact.json")"

# Bind the original candidate's embedded bytes to its tracked blueprint.
vesting_code="$(jq -er '.validators[] | select(.title == "linear_vesting.linear_vesting.spend") | .compiledCode' "$repo_dir/onchain/plutus.json")"
frozen_vesting="$(sed -n 's/.*singleCborEncodedScriptFromHexM "\([0-9a-f]*\)".*/\1/p' "$repo_dir/formal/Formal/Vesting/Linear/Blueprint/Types.lean")"
test "$vesting_code" = "$frozen_vesting"
printf '%s\n' 'UP-007 artifact identity checks passed.'

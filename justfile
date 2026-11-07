# Root task runner: every command CI runs is a recipe here, so local runs and
# CI cannot drift. Recipes assume the toolchain is present — run `just doctor`
# first, and `npm ci` in the package you are about to test.

set shell := ["bash", "-uc"]

default:
    @just --list

# Rewrite formatting in place (Biome for TS/JS/JSON).
fmt:
    npm run format

# Check formatting without writing: Biome + aiken fmt.
fmt-check:
    npm run format:check
    cd onchain && aiken fmt --check

# Lint with warnings as errors: Biome format, lint and import order.
lint:
    npm run lint:check

# On-chain: aiken check, aiken build, fail if plutus.json drifted.
onchain:
    cd onchain && aiken check --max-success=100
    cd onchain && aiken build
    cd onchain && git diff --exit-code -- plutus.json

# Re-pin the off-chain blueprints from onchain/plutus.json (writes).
blueprints:
    npm run blueprint:update

# Fail when the pinned blueprints drift from onchain/plutus.json.
blueprints-check:
    npm run blueprint:check

# MeshJS lib: typecheck + unit tests.
unit:
    cd offchain/meshjs/lib && npm run typecheck
    cd offchain/meshjs/lib && npm test

# MeshJS e2e on an ephemeral Yaci devnet; `just e2e <file>` runs one suite.
e2e file="":
    cd offchain/meshjs/e2e && npm run typecheck
    cd offchain/meshjs/e2e && REQUIRE_DEVNET=1 npm run test:devnet {{file}}

# Regenerate the tx3 TypeScript clients (gitignored; CI runs this too).
tx3-codegen:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in offchain/tx3/*/; do
      if [ -f "${dir}trix.toml" ]; then
        (cd "$dir" && trix codegen --plugin ts-client)
      fi
    done

# Tx3 suites on ephemeral dolos devnets; `just tx3 <protocol>` runs one.
tx3 protocol="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Protocol dir: settings, dao, smart_wallet, event-triggered-assets, vesting.
    cd offchain/tx3
    npm run typecheck
    if [ -n "{{protocol}}" ]; then
      npm run test:devnet -- "{{protocol}}/tests/devnet.test.ts"
    else
      npm run test:devnet
    fi

# Formal proofs (needs nix): re-check the Lean theorems on compiled bytecode.
formal:
    cd formal && just verify

# Everything CI runs, in CI's order.
ci: fmt-check lint blueprints-check onchain unit e2e tx3

# Everything CI runs plus the formal proofs.
all: ci formal

# Preflight: check node, aiken, Java 21, yaci-devkit, trix, dolos.
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    ok() { echo "✓ $1"; }
    fail() { echo "✗ $1" >&2; exit 1; }

    command -v node >/dev/null || fail "node not on PATH"
    want="$(cat .nvmrc)"
    have="$(node -p 'process.versions.node')"
    [ "${have%%.*}" = "$want" ] || fail "node $have but .nvmrc wants $want.x — switch node"
    ok "node $have"

    command -v aiken >/dev/null || fail "aiken not on PATH"
    ok "aiken $(aiken --version | awk '{print $2}')"

    command -v java >/dev/null || fail "java not on PATH (needs 21, e.g. temurin)"
    java_major="$(java -version 2>&1 | head -n1 | grep -oE '[0-9]+' | head -n1)"
    [ "$java_major" = "21" ] || fail "java $java_major but the devnet needs 21"
    ok "java 21"

    yaci="offchain/meshjs/e2e/node_modules/.bin/yaci-devkit"
    if [ -x "$yaci" ]; then
      ok "yaci-devkit (pinned, e2e node_modules)"
    elif command -v yaci-devkit >/dev/null; then
      echo "! yaci-devkit is global; the pinned version is an e2e devDependency" >&2
      echo "  run \`npm ci\` in offchain/meshjs/e2e" >&2
    else
      fail "yaci-devkit not installed — run \`npm ci\` in offchain/meshjs/e2e"
    fi

    command -v trix >/dev/null || fail "trix not on PATH — run \`tx3up\`"
    ok "trix $(trix --version)"

    command -v dolos >/dev/null || fail "dolos not on PATH — run \`tx3up\`"
    dolos_version="$(dolos --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
    if [ "$(printf '%s\n' "1.4.0" "$dolos_version" | sort -V | head -n1)" != "1.4.0" ]; then
      fail "dolos $dolos_version < 1.4.0 — upgrade (see offchain/tx3/README.md)"
    fi
    ok "dolos $dolos_version"

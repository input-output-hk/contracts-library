# Root task runner: every command CI runs is a recipe here, so local runs and
# CI cannot drift. Recipes assume the toolchain is present — run `just doctor`
# first. `just install` runs npm ci in every package (or pass one: root|lib|e2e|tx3).

set shell := ["bash", "-uc"]

default:
    @just --list

# npm ci in one package (root|lib|e2e|tx3), or in all of them (default).
install package="":
    #!/usr/bin/env bash
    set -euo pipefail
    npmci() { (cd "$1" && npm ci); }
    case "{{package}}" in
      "")   npmci . && npmci offchain/meshjs/lib && npmci offchain/meshjs/e2e && npmci offchain/tx3 ;;
      root) npmci . ;;
      lib)  npmci offchain/meshjs/lib ;;
      e2e)  npmci offchain/meshjs/e2e ;;
      tx3)  npmci offchain/tx3 ;;
      *)    echo "unknown package '{{package}}' — expected root|lib|e2e|tx3" >&2; exit 1 ;;
    esac

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

# Nightly-strength property tests, as .github/workflows/onchain-pbt.yml runs.
pbt:
    cd onchain && aiken check --max-success=1000

# Re-pin the off-chain blueprints from onchain/plutus.json (writes).
blueprints:
    npm run blueprint:update

# Fail when the pinned blueprints drift from onchain/plutus.json.
blueprints-check:
    npm run blueprint:check

# Build the MeshJS lib that the e2e and tx3 suites import (installs deps too).
build: (install "lib")
    cd offchain/meshjs/lib && npm run build

# MeshJS lib: typecheck + unit tests.
unit:
    cd offchain/meshjs/lib && npm run typecheck
    cd offchain/meshjs/lib && npm test

# MeshJS e2e on an ephemeral Yaci devnet; `just e2e <file>` runs one suite.
e2e file="":
    cd offchain/meshjs/e2e && npm run typecheck
    cd offchain/meshjs/e2e && REQUIRE_DEVNET=1 npm run test:devnet {{file}}

# Install the pinned tx3 toolchain (trix, dolos) under ~/.tx3 — same pin as CI.
tx3-toolchain:
    #!/usr/bin/env bash
    # Both layers are pinned so a toolchain release cannot silently change
    # what runs: the tx3up installer at its release tag, and the toolchain
    # manifest via `tx3up install --release` (tx3-lang/toolchain tags; this
    # one ships trix ^0.28.0, dolos ^1.6.1). Bump deliberately, then re-run
    # the devnet suites (`just tx3`).
    set -euo pipefail
    curl -LsSf https://github.com/tx3-lang/tx3up/releases/download/v0.8.0/tx3up-installer.sh | sh
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    tx3up install --release sha-3f2296a
    # CI runs each step in a fresh shell: hand the toolchain bins to
    # GITHUB_PATH. Locally the tx3up installer already put them on PATH.
    for d in "$HOME"/.tx3/*/bin; do
      if [ -d "$d" ] && [ -n "${GITHUB_PATH:-}" ]; then
        echo "$d" >> "$GITHUB_PATH"
      fi
    done

# Regenerate the tx3 TypeScript clients (gitignored; CI runs this too).
tx3-codegen:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in offchain/tx3/*/; do
      if [ -f "${dir}trix.toml" ]; then
        (cd "$dir" && trix codegen --plugin ts-client)
      fi
    done

# Fail when dolos < 1.4.0 (POSIXTime-in-seconds bug); `just tx3` runs it first.
dolos-check:
    #!/usr/bin/env bash
    # dolos < 1.4.0 injects Plutus POSIXTime in seconds during mempool
    # validation, so time-dependent validators fail cryptically
    # (see offchain/tx3/README.md).
    set -euo pipefail
    command -v dolos >/dev/null 2>&1 || { echo "dolos not on PATH — run \`just tx3-toolchain\`" >&2; exit 1; }
    version="$(dolos --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
    if [ "$(printf '%s\n' "1.4.0" "$version" | sort -V | head -n1)" != "1.4.0" ]; then
      echo "dolos $version < 1.4.0 — upgrade it (see offchain/tx3/README.md, dolos version requirement)" >&2
      exit 1
    fi
    echo "dolos $version"

# Tx3 suites on ephemeral dolos devnets; `just tx3 <protocol>` runs one.
tx3 protocol="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Protocol dir: settings, dao, smart_wallet, event-triggered-assets, vesting.
    just dolos-check
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

# Everything the PR CI workflow (ci.yml) runs, in its order.
ci: (install "root") fmt-check lint blueprints-check onchain build unit (install "e2e") e2e

# Everything the tx3 devnet workflow (tx3-devnet.yml) runs: prep, then suites.
tx3-suite: build (install "e2e") tx3-codegen (install "tx3") tx3

# Everything the CI workflows run plus the formal proofs.
all: ci tx3-suite formal

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

    command -v java >/dev/null || fail "java not on PATH (needs 21+, e.g. temurin)"
    java_major="$(java -version 2>&1 | head -n1 | grep -oE '[0-9]+' | head -n1)"
    [ "${java_major:-0}" -ge 21 ] || fail "java $java_major but the devnet needs 21+"
    ok "java $java_major"

    yaci="offchain/meshjs/e2e/node_modules/.bin/yaci-devkit"
    if [ -x "$yaci" ]; then
      yaci_version="$(node -e "console.log(require('./offchain/meshjs/e2e/node_modules/@bloxbean/yaci-devkit/package.json').version)")"
      ok "yaci-devkit $yaci_version (pinned, e2e node_modules)"

      # Version-isolated component cache used by the e2e devnet script
      # (offchain/meshjs/e2e/scripts/devnet-test.sh); flag a mismatched cache.
      platform="offchain/meshjs/e2e/node_modules/@bloxbean/yaci-devkit-linux-x64"
      [ -d "$platform" ] || platform="offchain/meshjs/e2e/node_modules/@bloxbean/yaci-devkit-macos-arm64"
      yaci_home="${YACI_HOME:-$PWD/.yaci/$yaci_version}"
      if [ -f "$platform/config/download.properties" ]; then
        expected_node="$(grep -E '^node\.version=' "$platform/config/download.properties" | cut -d= -f2)"
        expected_yano="$(grep -E '^yano\.version=' "$platform/config/download.properties" | cut -d= -f2)"
        if [ ! -d "$yaci_home" ]; then
          echo "• no Yaci component cache at $yaci_home yet (the first e2e run downloads it)"
        else
          if [ -x "$yaci_home/cardano-node/bin/cardano-node" ]; then
            have_node="$("$yaci_home/cardano-node/bin/cardano-node" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
            if [ -n "$expected_node" ] && [ "$have_node" != "$expected_node" ]; then
              echo "! cached cardano-node $have_node != expected $expected_node — remove $yaci_home to re-download" >&2
            else
              ok "yaci cache cardano-node $have_node"
            fi
          fi
          yano_manifest="$yaci_home/components/yano/yano-distribution-v1.json"
          if [ -f "$yano_manifest" ]; then
            have_yano="$(node -e "console.log(require('$yano_manifest').version)")"
            if [ -n "$expected_yano" ] && [ "$have_yano" != "$expected_yano" ]; then
              echo "! cached yano $have_yano != expected $expected_yano — remove $yaci_home to re-download" >&2
            else
              ok "yaci cache yano $have_yano"
            fi
          fi
        fi

        # The node's Unix socket path has a 108-byte limit (sun_path).
        socket="$yaci_home/local-clusters/default/node/node.sock"
        if [ ${#socket} -gt 107 ]; then
          fail "YACI_HOME is too long for the node socket (${#socket} > 107 bytes): $yaci_home"
        fi
      fi
    elif command -v yaci-devkit >/dev/null; then
      echo "! yaci-devkit is global; the pinned version is an e2e devDependency" >&2
      echo "  run \`just install e2e\`" >&2
    else
      fail "yaci-devkit not installed — run \`just install e2e\`"
    fi

    # The version-isolated cache above replaces the old global ~/.yaci-cli
    # reuse trap: another Yaci version cannot leave a cardano-node behind that
    # this one picks up (`DijkstraGenesisFile` / key-not-found crashes).

    command -v trix >/dev/null || fail "trix not on PATH — run \`tx3up\`"
    ok "trix $(trix --version)"

    just dolos-check

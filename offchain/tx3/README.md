# Tx3 off-chain — devnet tests

This directory holds the **Tx3** reference off-chain and its end-to-end tests.
The tests drive an ephemeral [dolos](https://github.com/txpipe/dolos) devnet
booted by [`trix devnet`](https://github.com/tx3-lang/trix), orchestrated from
vitest by the harness in [`devnet/utils.ts`](devnet/utils.ts).

## How it works

- **Genesis**: the committed [`settings/devnet.toml`](settings/devnet.toml)
  funds a single faucet address at genesis. That address belongs to the fixed
  throwaway keypair committed in
  [`devnet/faucet.ts`](devnet/faucet.ts) (TEST ONLY) — trix never sees key
  material, only the public address.
- **Lifecycle**: one fresh devnet per test *run*. `TrixDevnet.start()` deletes
  trix's `.tx3` state directory, boots `trix devnet` as a child process, and
  healthchecks the endpoints trix generates (`.tx3/dolos/dolos.toml`). Teardown
  kills the process tree and wipes state, so every run starts from a clean
  chain.
- **Funding**: tests create random wallets and fund them with real
  `devnet_pay` transactions (see the TEST KIT section of
  [`settings/main.tx3`](settings/main.tx3)), serialized because the live
  faucet holds exactly one spendable UTxO.
- **Fixtures**: the always-true authorizer script is published on-chain as a
  reference-script UTxO via `cardano::publish`, and its stake credential is
  registered once per run for the withdraw-0 paths.

## Requirements

- Node.js + npm dependencies (`just install tx3`, or `just install` for every package).
- The **tx3 toolchain** (`trix`, plus the dolos it spawns) under `~/.tx3`, at
  the same pinned release CI uses:

  ```bash
  just tx3-toolchain
  ```

- **dolos ≥ 1.4.0**: the pinned toolchain enforces this, and `just tx3`
  re-checks it (`just dolos-check`). Older versions inject Plutus `POSIXTime`
  in *seconds* during mempool validation, so time-dependent spend validators
  fail.

## Running the tests

**Before the tests:** build the MeshJS library the suites import, install the
MeshJS e2e dependencies (the event-triggered suite imports the vendored CIP-113
core blueprint/helpers from there), and generate the TypeScript clients
(gitignored) — the same recipes CI runs:

```bash
just build         # npm ci + build of offchain/meshjs/lib
just install e2e
just tx3-codegen   # trix codegen for every protocol with a trix.toml
```

The event-triggered suite deploys the vendored CIP-113 core itself through the
protocol's `core_init_*` TEST KIT transactions (registry, issuance template,
upgrade config and protocol params), then drives the real module validators:
create the vault, register the instrument, permissionless unit deposits, the
transfer and `commit` opt-in paths, owner-signed and issuer-triggered coupon
claims, burn-to-pay redemptions and both graduation paths.

Then run the suite (from `offchain/tx3`):

```bash
npm run test:devnet          # all protocols
npm run test:settings        # or: npx vitest run settings/tests/devnet.test.ts
npm run test:dao             # or: npx vitest run dao/tests/devnet.test.ts
npm run test:smart-wallet    # or: npx vitest run smart_wallet/tests/devnet.test.ts
npm run test:event-triggered # or: npx vitest run event-triggered-assets/tests/devnet.test.ts
npm run test:upgradeability  # or: npx vitest run upgradeability/tests/devnet.test.ts
npm run test:vesting         # or: npx vitest run vesting/tests/devnet.test.ts
```

A single test by name:

```bash
npx vitest run settings/tests/devnet.test.ts -t 'launches, proposes, applies, and closes'
```

Set `DEBUG_TRIX=1` to stream the trix/dolos logs while booting.

## CI

The tx3 devnet suites are the slowest CI leg (~45 min), so they don't gate
PRs: `.github/workflows/tx3-devnet.yml` runs them nightly and on demand —
Actions → "Tx3 devnet (nightly)" → Run workflow, or
`gh workflow run tx3-devnet.yml --ref <branch>` before merging tx3 changes.
It installs the pinned tx3 toolchain, generates the TypeScript clients, then
`just tx3` boots one ephemeral dolos devnet per protocol, serially (fixed
ports), and always tears them down. Locally the same suites run via
`just tx3-suite` (or `just all` for everything).

## Troubleshooting

- **Startup fails with ports already in use** — trix's generated config uses
  fixed ports (TRP 8164 / minibf 3164 / gRPC 5164). Kill any stray `dolos`
  from an earlier crashed run (`pkill dolos`) and retry; the harness wipes
  `.tx3` on start and stop, so stale state is otherwise self-healing.
- **`-32003 tx script returned failure` on time-dependent validators** — see
  the dolos version requirement above.

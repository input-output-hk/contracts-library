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

- Node.js + workspace dependencies installed (`npm install` in this folder).
- The **tx3 toolchain** (`trix`, plus the dolos it spawns) under `~/.tx3`:

  ```bash
  curl -LsSf https://github.com/tx3-lang/tx3up/releases/latest/download/tx3up-installer.sh | sh
  tx3up
  ```

- **dolos ≥ 1.4.0**: older versions inject Plutus `POSIXTime` in *seconds*
  during mempool validation, so time-dependent spend validators fail with an
  opaque `-32003 tx script returned failure`. As of this writing `tx3up` may
  still install dolos 1.3.2 — check `dolos --version` and replace
  `~/.tx3/stable/bin/dolos` with a newer release if needed.

## Running the tests

> **Before the tests:** generate the TypeScript client (gitignored). From the
> protocol directory where `trix.toml` lives:

```bash
cd offchain/tx3/settings
trix codegen --plugin ts-client

cd ..
npm run test:devnet      # or: npx vitest run settings/tests/devnet.test.ts
```

A single test by name:

```bash
npx vitest run settings/tests/devnet.test.ts -t 'launches, proposes, applies, and closes'
```

Set `DEBUG_TRIX=1` to stream the trix/dolos logs while booting.

## Troubleshooting

- **Startup fails with ports already in use** — trix's generated config uses
  fixed ports (TRP 8164 / minibf 3164 / gRPC 5164). Kill any stray `dolos`
  from an earlier crashed run (`pkill dolos`) and retry; the harness wipes
  `.tx3` on start and stop, so stale state is otherwise self-healing.
- **`-32003 tx script returned failure` on time-dependent validators** — see
  the dolos version requirement above.

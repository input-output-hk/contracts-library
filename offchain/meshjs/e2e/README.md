# Linear Vesting: MeshJS end-to-end tests

These tests run the published library (`@contracts-library/vesting-meshjs`, consumed by its package name via `file:../lib`) against a real local [Yaci DevKit](https://devkit.yaci.xyz) devnet. They are a **separate package**, so they exercise the library exactly as a downstream consumer would and never ship with it.

## What they cover

Through the public API (`buildLockTx` / `buildClaimTx` / `buildCancelTx`):

- Lock, then **partial claim** mid-schedule (continuation keeps the required remainder);
- **Full claim** after `end_time` (no continuation);
- **Locker recovery** after `recovery_time`;
- **Script-credential beneficiary** claim via the `authorizer` (withdraw-0): an always-approving authorizer succeeds, and a reject-withdraw authorizer is rejected. The authorizer scripts are test fixtures (see below).

As raw malicious transactions (built with `MeshTxBuilder` + the library's public encoders, the way an attacker would), each asserted to be **rejected** by the on-chain validator:

- Over-claim (continuation short of the required remainder);
- Claim missing the beneficiary signature;
- Tampered continuation datum;
- Cancel before `recovery_time`;
- Cancel by a non-locker.

## Running locally

```sh
npm install -g @bloxbean/yaci-devkit   # one-time
npm install
npm run test:devnet
```

`test:devnet` (`scripts/devnet-test.sh`) starts an ephemeral devnet, waits for its API to serve blocks, runs the suite, and always tears the devnet down. If yaci-devkit is not installed it falls back to `npm test` with no devnet, and the suite **skips itself** (so it is safe to run anywhere).

`npm test` alone runs the suite against whatever devnet is already reachable (or skips). Endpoints come from env, matching the shared lifecycle convention: `INDEXER_URL` / `YACI_STORE_URL` for the store API (default `http://localhost:8080/api/v1/`) and `YACI_ADMIN_URL` for the admin API (default `http://localhost:10000`).

## Authorizer fixtures

The script-credential tests use two tiny Plutus V3 authorizer scripts compiled from [`fixtures/aiken`](./fixtures/aiken): 
- `always_true` (approves everything)
- `reject_withdraw` (rejects withdrawals, approves the rest so its stake credential can still be registered). 

Their compiled CBOR is committed in [`src/fixtures.ts`](./src/fixtures.ts), so running the tests needs no Aiken toolchain; rebuild the project there only to regenerate them. The tests register the authorizer's stake credential (a withdraw-0 needs a registered reward account) before claiming.

## CI

`.github/workflows/ci.yml` runs these on every push and PR to `main`: it installs Yaci DevKit, starts the devnet, waits until the store API is serving blocks, builds the library, and runs this suite.

## Notes on time

A devnet's slot numbering starts at its own genesis, not preview/preprod/mainnet, so the tests derive the devnet's `SlotConfig` from a live block and pass it to the builders via `customSlotConfig`. Funding uses the Yaci admin API through `YaciProvider.addressTopup`.

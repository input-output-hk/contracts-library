# Vesting: MeshJS off-chain

This directory groups the MeshJS off-chain work for the linear vesting contract:

- [`lib/`](./lib): the published library (`@contracts-library/vesting-meshjs`): transaction builders, datum/redeemer encoders, the pinned blueprint, and unit tests. This is what consumers install.
- [`e2e/`](./e2e): end-to-end tests that run the library against a local [Yaci DevKit](https://devkit.yaci.xyz) devnet. A separate package that depends on `lib/` by its public name, so the tests consume the library exactly as a downstream user would and never ship with it.

Future off-chain languages follow the same shape (e.g. `offchain/tx3/lib` + `offchain/tx3/e2e`).

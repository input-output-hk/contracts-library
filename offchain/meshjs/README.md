# MeshJS off-chain

This directory groups the MeshJS off-chain work for all the contracts:

- [`lib/`](./lib): the published library (`@contracts-library/meshjs`): transaction builders, datum/redeemer encoders, the pinned blueprint, and unit tests. This is what consumers install.
- [`e2e/`](./e2e): end-to-end tests that run the library against a local [Yaci DevKit](https://devkit.yaci.xyz) devnet. A separate package that depends on `lib/` by its public name, so the tests consume the library exactly as a downstream user would and never ship with it.

The Tx3 reference implementations live under [`offchain/tx3/`](../tx3): one
directory per protocol with its `main.tx3` interface, a generated TypeScript
client, and a devnet test suite; see [`offchain/tx3/README.md`](../tx3/README.md).

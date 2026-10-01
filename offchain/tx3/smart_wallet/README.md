# Smart Wallet — Tx3 off-chain (core lifecycle)

Reference **Tx3** implementation of the smart wallet action set, mirroring the
on-chain multivalidator in
[`onchain/validators/smart_wallet`](../../../onchain/validators/smart_wallet/smart_wallet.ak)
and the MeshJS builders in
[`offchain/meshjs/lib/src/smart_wallet`](../../meshjs/lib/src/smart_wallet).
The language-agnostic behavior is specified in
[`docs/smart-wallet/spec.md`](../../../docs/smart-wallet/spec.md).

A wallet is a single UTxO at the parameterized `smart_wallet` script address,
identified by a one-shot NFT minted under the script's own policy. Its inline
datum carries the delegated `withdrawals` map and the `depositor` credential;
the `admin` that creates, reconfigures, and closes the wallet is a compile-time
script parameter. The base M-of-N floor (`members`, `threshold`) is read at
runtime from a settings UTxO, located by its NFT via **reference input**.

## Action set

| Template | Purpose |
| --- | --- |
| `launch_settings` | Mint a settings instance holding the wallet's `WalletConfig` (fixture / consumer convenience). |
| `mint_wallet` | One-shot create: spend the seed UTxO, mint the wallet NFT, write the initial datum. |
| `deposit` | The depositor adds ADA; datum and value otherwise preserved. |
| `spend` | The M-of-N floor signs; the wallet pays out and continues with the remainder. |
| `update_config` | The admin rewrites the depositor; withdrawals and value are preserved. |
| `close` | The admin burns the wallet NFT and releases the funds; irreversible. |

Each builder is a Tx3 transaction template in [`main.tx3`](./main.tx3); the
TypeScript client is generated from it with `trix codegen`.

## Parameters (`env`)

The `smart_wallet` multivalidator is parameterized off-chain (Tx3 has no
parameter application): the test parameterizes the script with MeshJS
`applyParamsToScript` and passes the results as environment values.

| Env value | Meaning |
| --- | --- |
| `wallet_hash` | Hash of the parameterized `smart_wallet` validator (also the NFT policy id). |
| `wallet_script` | Single-CBOR flat validator script (mint/spend witness). |
| `wallet_token_name` | Asset name of the wallet's identifying NFT. |
| `settings_hash` | Hash of the parameterized settings validator (minted by `launch_settings`). |
| `settings_script` | Single-CBOR flat settings validator script. |

Parties bound at runtime: `Admin`, `Depositor`, `Member`, `Wallet` (wallet
script address), `Settings` (settings script address). This reference
implements the **key-authorized** paths only: each party is bound to the key
credential the validator authorizes. The M-of-N floor supports N members
on-chain, but a Tx3 party is a single key, so this reference and its tests use a
1-of-1 wallet.

## Scope: delegated withdrawal scripts are not expressible yet

The on-chain `Mint`, `UpdateConfig` (adding/removing scripts), and `Close`
endpoints require CIP-69 `publish` handlers to run, i.e. a
`RegisterCredential` / `UnregisterCredential` certificate **in the same
transaction**. The Tx3 v1beta0 language has no block for Cardano
registration/unregistration certificates (only `withdrawal`,
`*_delegation_certificate`, `plutus_witness`, `native_witness`,
`treasury_donation`, and `publish`), tracked upstream by
[tx3-lang/tx3#164](https://github.com/tx3-lang/tx3/issues/164).

Consequently every wallet produced by this reference carries an **empty
`withdrawals` map**, where the on-chain publication and unregistration checks
are vacuously true. Spending a wallet that already delegates to scripts remains
valid on-chain, but such a wallet cannot be produced or torn down by Tx3 until
upstream certificate support lands. The map's values are carried as an opaque
`Bytes` stand-in — Tx3 has no raw `Data` type — and are only usable empty
today.

## Running the tests

The suite boots an ephemeral [dolos](https://github.com/txpipe/dolos) devnet
via `trix devnet` and drives real transactions through the harness in
[`../devnet/utils.ts`](../devnet/utils.ts). Generate the TypeScript client
first (gitignored):

```bash
cd offchain/tx3/smart_wallet
trix codegen --plugin ts-client
```

Then run the suite (from `offchain/tx3`):

```bash
npm run test:smart-wallet
# or: npx vitest run smart_wallet/tests/devnet.test.ts
```

See [`../README.md`](../README.md) for toolchain requirements and
troubleshooting.

## Coverage

- **Happy path**: settings launch → mint → deposit → spend → update config →
  close, asserting the wallet's value and NFT lifecycle.
- **Attack paths**: M-of-N bypass, deposit removing value, deposit rewriting
  the datum, non-admin config update, and close without burning the NFT — each
  must fail phase-2 validation and leave the wallet UTxO untouched.

# Linear Vesting — MeshJS off-chain

Transaction builders for the [linear vesting](../../../specs/vesting/linear-vesting.md) contract. This is the primary developer-facing API: you can lock and claim vested funds without reading the Aiken validator.

- **Spec**: [`specs/vesting/linear-vesting.md`](../../../specs/vesting/linear-vesting.md)
- **On-chain**: [`onchain/`](../../../onchain), pinned via `src/blueprint.ts` (validator hash `fa1144f1…`, Aiken v1.1.21, Plutus V3).

## The model in one paragraph

A vesting UTxO locks a bundle of assets for a `beneficiary` and releases it linearly from `startTime` to `endTime` (POSIX **milliseconds**). At any moment the beneficiary may claim whatever has vested; the rest must stay locked under the **same datum**. Before `startTime` nothing is claimable; at/after `endTime` everything is. The datum never changes; each claim derives the vested amount purely from the current time. After `recoveryTime` (which must be after `endTime`), the `locker` may recover whatever remains via `buildCancelTx`.

## Install

```sh
npm install @contracts-library/vesting-meshjs @meshsdk/core
```

## API


| Export | Purpose |
|---|---|
| `buildLockTx(params)` | Create a vesting instance. |
| `buildClaimTx(params)` | Withdraw the vested portion (beneficiary; key or script via `authorizer`). |
| `buildCancelTx(params)` | Recover the remainder after `recoveryTime` (locker; key or script via `authorizer`). |
| `ScriptAuthorizer` | Describes how to invoke a script credential's approving script. |
| `vestingScript()` / `vestingScriptAddress(networkId)` | The pinned Plutus V3 script and its address. |
| `vestedQuantity(total, start, end, now)` | Schedule math (mirrors on-chain). |
| `requiredRemainder(datum, now)` | Per-asset amount that must stay locked. |
| `vestingDatumToData` / `claimRedeemer` | CBOR encoders matching the blueprint. |


### Datum shape

```ts
import type { VestingDatum } from "@contracts-library/vesting-meshjs";

const now = Date.now();
const datum: VestingDatum = {
  beneficiary: { kind: "key", hash: beneficiaryPubKeyHash }, // 56 hex chars
  locker: { kind: "key", hash: lockerPubKeyHash },
  vesting: [
    { policyId: "", assetName: "", total: 100_000_000n },     // 100 ada
    { policyId: tokenPolicy, assetName: tokenNameHex, total: 1_000n },
  ],
  startTime: now,
  endTime: now + 30 * 24 * 60 * 60 * 1000,        // +30 days, in ms
  recoveryTime: now + 60 * 24 * 60 * 60 * 1000,   // +60 days (must be > endTime)
};
```

`policyId: ""` / `assetName: ""` is ada. Quantities are `bigint`. The `locker` can recover anything still locked after `recoveryTime`.

## Full example

```ts
import { MeshTxBuilder, BlockfrostProvider, MeshWallet } from "@meshsdk/core";
import { buildLockTx, buildClaimTx } from "@contracts-library/vesting-meshjs";

const provider = new BlockfrostProvider(BLOCKFROST_KEY);
const wallet = new MeshWallet({ networkId: 0, fetcher: provider, submitter: provider, key: {/* ... */} });

// --- Lock ---
const lockTx = await buildLockTx({
  txBuilder: new MeshTxBuilder({ fetcher: provider, submitter: provider }),
  datum,
  utxos: await wallet.getUtxos(),
  changeAddress: await wallet.getChangeAddress(),
  networkId: 0,
});
const lockTxHash = await wallet.submitTx(await wallet.signTx(lockTx));

// --- Claim (partial or full, depending on `now`) ---
const claimTx = await buildClaimTx({
  txBuilder: new MeshTxBuilder({ fetcher: provider, submitter: provider }),
  vestingUtxo,                 // the script UTxO produced by the lock
  datum,                       // the same terms you locked with
  now: Date.now(),             // becomes the validity-range lower bound
  beneficiaryAddress: await wallet.getChangeAddress(),
  collateralUtxo: (await wallet.getCollateral())[0],
  utxos: await wallet.getUtxos(),
  network: "preprod",
});
await wallet.submitTx(await wallet.signTx(claimTx));
```

The claimed funds flow to `beneficiaryAddress` via change; the required remainder is returned to the script automatically. When `now >= endTime`, no continuing output is created and the whole bundle is taken.

```ts
// --- Cancel (locker recovers the remainder, only after recoveryTime) ---
const cancelTx = await buildCancelTx({
  txBuilder: new MeshTxBuilder({ fetcher: provider, submitter: provider }),
  vestingUtxo,
  datum,
  now: Date.now(),            // must be >= datum.recoveryTime
  lockerAddress: await lockerWallet.getChangeAddress(),
  collateralUtxo: (await lockerWallet.getCollateral())[0],
  utxos: await lockerWallet.getUtxos(),
  network: "preprod",
});
await lockerWallet.submitTx(await lockerWallet.signTx(cancelTx));
```

## Script beneficiaries and lockers (pluggable authorization)

A `{ kind: "key", hash }` credential authorizes by signing; the library adds the required signer for you, so nothing extra is needed.

A `{ kind: "script", hash }` credential (a multisig, DAO, smart wallet, ...) authorizes by being **invoked** in the same transaction via the withdraw-0 pattern (it runs as a zero-ada reward withdrawal). Just describe that script with an `authorizer` and pass it; the library checks its hash matches the credential, derives the reward address, and wires the withdrawal in:

```ts
await buildClaimTx({
  ...,
  authorizer: { scriptCbor: myMultisigScriptCbor, redeemer: myApproval },
});
```

The same `authorizer` field works on `buildCancelTx` for a script `locker`. You do not touch the transaction builder.

`ScriptAuthorizer` options:

| Field | Meaning |
|---|---|
| `scriptCbor` | The approving script, inlined (hex). |
| `reference` | Or a UTxO carrying it as a reference script (cheaper for reusable authorizers). |
| `scriptHash` | Optional; computed from `scriptCbor`, or supplied with `reference`. |
| `redeemer` | What the approving script expects. Defaults to unit. |
| `version` | Plutus version of the authorizer. Default `"V3"`. |
| `manual` | Escape hatch: set `true` if you attached the withdrawal to the `txBuilder` yourself. |


> **Setup note:** the withdraw-0 pattern requires the authorizer's **stake script credential to be registered once** (a small one-time deposit). The builder produces the withdrawal; registering the credential is a one-time setup step the consumer performs. Adding a new authorization scheme never requires changing this library (ARCHITECTURE.md §3); you only pass its script and redeemer.

## Custom networks (Yaci, private chains)

`buildClaimTx` / `buildCancelTx` turn the desired `now` into a slot using the slot config for `network` (`preview` / `preprod` / `mainnet`). On any other chain (a local Yaci devnet, a private network) that mapping is wrong, so pass its slot config explicitly:

```ts
await buildClaimTx({
  ...,
  customSlotConfig: { zeroTime, zeroSlot: 0, slotLength: 1000, startEpoch: 0, epochLength: 432000 },
});
```

You only need `customSlotConfig` off the three public networks; otherwise leave it unset.

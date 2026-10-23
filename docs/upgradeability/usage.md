# Upgradeability — Usage Guide

How to deploy, operate, and consume the upgradeability building block: a
**registry** held in a settings UTxO (#20) that maps a protocol validator's own
hash to the delegate script that currently governs it.

Two mechanisms share this registry:

- **Forced** (beacon indirection): a thin forwarder delegates every path to the
  registered **logic** script; a repoint applies to all users at once and never
  moves funds.
- **Opt-in** (migration): a validator keeps its native logic and forwards only
  its `Upgrade` path to the registered **migration** script; each user moves
  their own UTxO, and consent is enforced natively.

> **Source of truth.** Behaviour, threat model, and invariants are in
> [`spec.md`](spec.md). This guide only covers day-to-day usage.

| Part | Where |
|---|---|
| Registry + predicates | [`onchain/lib/upgradeability/`](../../onchain/lib/upgradeability/) |
| Forced reference validators | [`onchain/validators/upgradeability/counter_forwarder.ak`](../../onchain/validators/upgradeability/counter_forwarder.ak), [`counter_logic.ak`](../../onchain/validators/upgradeability/counter_logic.ak) |
| Opt-in reference validators | [`onchain/validators/upgradeability/counter_v1.ak`](../../onchain/validators/upgradeability/counter_v1.ak), [`counter_migration.ak`](../../onchain/validators/upgradeability/counter_migration.ak), [`counter_v2.ak`](../../onchain/validators/upgradeability/counter_v2.ak) |
| MeshJS builders | [`offchain/meshjs/lib/src/upgradeability/`](../../offchain/meshjs/lib/src/upgradeability/) |
| Unit tests | [`offchain/meshjs/lib/test/upgradeability.test.ts`](../../offchain/meshjs/lib/test/upgradeability.test.ts) |
| e2e (Yaci devnet) | [`offchain/meshjs/e2e/test/upgradeability.e2e.test.ts`](../../offchain/meshjs/e2e/test/upgradeability.e2e.test.ts) |
| Compiled blueprint | [`onchain/plutus.json`](../../onchain/plutus.json) |

The `counter_*` validators under `onchain/validators/upgradeability/` are a
**non-normative demo**; a real protocol supplies its own state and its own logic
/ migration scripts.

## Contents

- [The registry](#the-registry)
- [Forced: deploy a forwarder + logic](#forced-deploy-a-forwarder--logic)
- [Opt-in: deploy V1 + migration + V2](#opt-in-deploy-v1--migration--v2)
- [Upgrading](#upgrading)
- [Reading the registry](#reading-the-registry)
- [Off-chain usage (MeshJS)](#off-chain-usage-meshjs)
- [Gotchas and safety notes](#gotchas-and-safety-notes)

## The registry

The registry lives in the `current` value of a settings UTxO (#20): a
`Map<ScriptHash, ScriptHash>`. Deploy a settings instance exactly as described
in the [settings usage guide](../settings/usage.md) — the reference `settings`
validator accepts any value, so a map needs no change. Consumers reject a
malformed registry at spend time (`decode_registry`); the reference validator
does not constrain the shape on-chain.

Because the registry is a settings value, **changing it is a normal
`Propose` → wait `apply_delay` → `Apply`** flow, authorized by
`propose_auth` / `apply_auth`. Use the existing settings builders
(`buildProposeTx` / `buildApplyTx`) with `newValue` = the encoded map; carry
forward every entry you are not changing.

## Forced: deploy a forwarder + logic

1. **Parameterize the forwarder** with the settings instance that holds the
   registry:

   ```aiken
   counter_forwarder(settings_policy, settings_token_name)
   ```

2. **Parameterize the logic** with the same settings instance:

   ```aiken
   counter_logic(settings_policy, settings_token_name)
   ```

   The logic is shared across every forwarder of that settings instance.

3. **Register** the pair: set `registry[forwarder_hash] = logic_hash` via the
   settings `Propose` / `Apply` flow.

4. **Lock state** at the forwarder's address. From then on, every spend must be
   accompanied by a zero withdrawal from `logic_hash`, which validates the
   forwarded input(s).

To **upgrade**, deploy a new logic script with the same parameterization and
repoint `registry[forwarder_hash]` to it. Funds stay put.

## Opt-in: deploy V1 + migration + V2

1. **Deploy V1** parameterized with the settings instance:

   ```aiken
   counter_v1(settings_policy, settings_token_name)
   ```

   Normal actions use V1's native logic; the `Upgrade` redeemer requires the
   owner's authorization plus the registered migration script.

2. **Deploy V2** (a new, immutable version — the demo's `counter_v2`).

3. **Deploy the migration script**, parameterized with the settings instance and
   the V2 address:

   ```aiken
   counter_migration(settings_policy, settings_token_name, v2_address)
   ```

4. **Register** `registry[v1_hash] = migration_hash` via the settings
   `Propose` / `Apply` flow.

To **migrate**, a user submits a transaction that spends their V1 UTxO with the
`Upgrade` redeemer, includes a zero withdrawal from the migration script, and
creates the V2 output at `v2_address`. The user signs (consent). V1 and V2
coexist; other users are unaffected.

## Upgrading

| Mechanism | Upgrade step | Who is affected | Funds move? |
|---|---|---|---|
| Forced | Repoint `registry[forwarder]` to a new logic hash | Everyone, at once | No |
| Opt-in | Deploy V2 + repoint `registry[V1]` to a migration script | Only users who migrate | Yes (V1 → V2) |

Both are governed, timelocked changes to the settings UTxO. A forced repoint is
**mandatory-timelocked**: the `apply_delay` is the users' window to inspect the
new logic (and, for opt-in, to migrate or exit) before it takes effect. The
anchor is chosen by the proposer, though: treat the delay as a scheduling tool,
not a hard guarantee against malicious governance (see the gotchas and
[settings spec §6.a](../settings/spec.md)).

## Reading the registry

On-chain, a consumer uses the library helpers:

```aiken
use upgradeability/registry.{get_registry, lookup}

let registry = get_registry(tx, settings_policy, settings_token_name)
let current_logic = lookup(registry, my_protocol_hash) // Option<ScriptHash>
```

Off-chain, the same read is a one-liner with the MeshJS helpers:

```ts
import { readRegistry } from "@contracts-library/meshjs";

const registry = readRegistry(settingsUtxo); // Map<hash, hash>
const logicHash = registry.get(forwarderHash);
```

The builders do this themselves before wiring anything (see below), so a stale
or missing registry entry surfaces as a clear error instead of a rejected
transaction.

## Off-chain usage (MeshJS)

The builders live in `offchain/meshjs/lib/src/upgradeability/` and follow the
settings conventions (a `MeshTxBuilder` + UTxOs in, cbor string out).

### 1. Parameterize and hash the scripts

```ts
import {
  counterForwarderScript,
  counterLogicScript,
  counterMigrationScript,
  counterScriptAddress,
  counterScriptHash,
  counterV1Script,
  counterV2Script,
} from "@contracts-library/meshjs";

const forwarder = counterForwarderScript(params);
const forwarderHash = counterScriptHash(forwarder); // the registry key
const logicHash = counterScriptHash(counterLogicScript(params)); // the value
const v2Address = counterScriptAddress(counterV2Script(), networkId);
const migration = counterMigrationScript({ ...params, v2Address }); // bech32 in
```

> On-chain, the migration validator takes `v2_address` as an Aiken `Address`.
> `counterMigrationScript` accepts the bech32 form and encodes the `Address`
> record for you (`addressToData`) — do not pass raw address bytes as the
> parameter.

### 2. Change the registry (settings builders, reused)

```ts
await buildRegistryProposeTx({
  ...settingsProposeArgs,
  registry: new Map([[forwarderHash, logicHash]]), // whole map, carried forward
});
// after apply_delay:
await buildRegistryApplyTx(settingsApplyArgs);
```

### 3. Forced: spend the forwarder through the registered logic

```ts
await buildForwardTx({
  txBuilder,
  forwarderScript: forwarder,
  logicAuthorizer: { scriptCbor: counterLogicScript(params).code }, // or { reference }
  forwarderUtxo,
  settingsUtxo, // added as a reference input
  utxos, changeAddress, collateralUtxo,
});
```

The builder reads the registry, checks the provided logic script matches the
registered delegate, and wires the withdraw-0 (`applyAuthorization`). Funds
never move.

### 4. Opt-in: tick natively, upgrade through the migration script

```ts
await buildCounterTickTx({ txBuilder, script: v1Script, counterUtxo, ... });

await buildUpgradeTx({
  txBuilder,
  v1Script,
  migrationAuthorizer: { scriptCbor: counterMigrationScript(params).code },
  v1Utxo,
  settingsUtxo,
  v2Address, // the blessed target
  utxos, changeAddress, collateralUtxo,
});
```

`buildUpgradeTx` requires the UTxO owner to be a key credential and adds it as
a required signer (consent), checks the migration script against the registry,
and re-creates the state at `v2Address` with `count` and `owner` preserved.

### 5. Running the tests

The builders are covered by unit tests (`npm test` in `offchain/meshjs/lib`)
and by an end-to-end suite against an ephemeral Yaci devnet
(`npm run test:devnet` in `offchain/meshjs/e2e`), which exercises the full
flow: launch with a registry, forced tick, registry propose/apply, migration
with consent, a forced repoint (and its on-chain rejection while routed to the
migration script), and the malformed-registry recovery.

## Gotchas and safety notes

- **A validator can never change its own logic.** Forced upgradeability only
  works if *every* path forwards from day one; a plain validator that adds an
  `Upgrade` path later is **opt-in**, not forced.
- **Forced repoints are a forced upgrade.** The registered logic runs for every
  user. Timelock and bounded governance are not optional. Prefer opt-in unless
  you genuinely must change behaviour for everyone.
- **Consent is native in opt-in.** Never move consent into the registered
  migration script: a governance repoint would then be able to drain funds.
- **Validate every forwarded input.** A logic / migration script must apply its
  checks to all of `forwarded_inputs(...)`, not just one.
- **Register the withdraw-0 stake credentials first.** The ledger only permits
  a withdrawal from a *registered* reward account: before any
  `buildForwardTx` / `buildUpgradeTx`, register the stake credentials of
  `logic_hash` and `migration_hash` — a stake-registration certificate over
  `serializeRewardAddress(hash, true, networkId)`, exactly what the e2e
  harness's `registerStakeCredential` does.
- **Migration is per-UTxO.** There is no global completeness guarantee, and no
  way to force a user off an opt-in V1.
- **The registry is only as good as its governance.** `propose_auth` /
  `apply_auth` and `apply_delay` are the whole trust surface; see the settings
  spec §6.
- **A malformed registry is a liveness hazard.** The reference settings validator
  accepts any value; a malformed map makes every consumer reject until governance
  fixes it (it can never be acted on).
- **Never `Close` the registry's settings instance.** The settings NFT is
  one-shot: closing burns it and the instance can never be relaunched, so every
  forced forwarder UTxO becomes permanently unspendable and opt-in V1 UTxOs lose
  their only value exit (they can still tick natively, never migrate). For a
  production registry use a settings fork without `Close`, or forbid closing at
  the governance layer.
- **The proposer anchors the delay.** `next_apply = now + apply_delay` is
  computed from the propose transaction's lower bound, which the proposer
  chooses; a malicious proposer can anchor it in the past and apply almost
  immediately (settings spec §6.a).
- **The settings UTxO needs enough lovelace for the registry.** A map of script
  hashes inflates the inline datum, which raises the min-UTxO of every
  continuation; 1.5 ADA is rejected on-chain (`BabbageOutputTooSmallUTxO`). The
  settings builders now start at 2.5 ADA — re-check the minimum if your registry
  grows.
- **Batched continuations are tagged, not first-match.** The demo datums carry
  a `prev_input: Option<OutputReference>` tag naming the UTxO each continuation
  continues (`None` only at the genesis lock), so every input settles by its
  own continuation: two same-count UTxOs cannot share one output, and one
  output can never satisfy the input it does not name. If your protocol adds
  state fields, keep the tag (or use a per-UTxO NFT) — a continuation lookup
  that ignores it would reintroduce the N→1 collapse.
- **Off-chain: MeshJS and Tx3 ship.** The MeshJS builders
  (`buildCounterTickTx`, `buildForwardTx`, `buildUpgradeTx`) live in
  `offchain/meshjs/lib/src/upgradeability/`; registry changes reuse the settings
  builders (`buildRegistryProposeTx` / `buildRegistryApplyTx`). The Tx3
  reference protocol and its devnet tests live in
  [`offchain/tx3/upgradeability/`](../../offchain/tx3/upgradeability/).

## Where to go next

- [Spec](spec.md) — full behavior, threat model, invariants, and the
  must-accept / must-reject characterization.
- [e2e suite](../../offchain/meshjs/e2e/test/upgradeability.e2e.test.ts) — the
  full flow on a Yaci devnet: launch with a registry, forced tick,
  propose/apply, migration with consent, a forced repoint (+ its on-chain
  rejection), and the malformed-registry recovery.
- [Settings usage guide](../settings/usage.md) — deploying and operating the
  settings instance that holds the registry.
- [Architecture](../ARCHITECTURE.md) — composability conventions shared by every
  contract in the library.

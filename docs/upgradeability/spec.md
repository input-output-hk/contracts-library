# Upgradeability Protocol Specification

## 1. Summary

Cardano validators are immutable and content-addressed: a validator's address is its code hash, so its logic can never change in place. This protocol provides the two eUTxO-native ways to evolve a deployed protocol:

- **Migration** (opt-in) — deploy new immutable code and let each user move *their own* UTxO to it.
- **Beacon indirection** (forced) — a thin forwarding validator delegates its logic to a script hash held in a governed registry, so the logic can be repointed without moving funds.

Both are **uses of the Config / Parameter Management primitive (#20)**. A single settings instance holds a **registry**: a map from a protocol validator's own script hash to the script hash of its currently-active delegate.

```
Registry : Map<ScriptHash, ScriptHash>
```

- The **key** is the immutable hash of the validator a user interacts with.
- The **value** is the script that must run.
- Registry changes reuse the settings protocol's `Propose` / `Apply` split, its `apply_delay` timelock, and its pluggable `propose_auth` / `apply_auth` authorization.

The two mechanisms differ only in **which redeemer paths forward**: a **forced** validator forwards every path (the value is the protocol's logic); an **opt-in** validator forwards only its `Upgrade` path (the value is the migration script).

This document specifies the reusable predicates (`onchain/lib/upgradeability/`) and their trust model. The `counter_*` reference validators are a non-normative demo used to exercise the mechanics.

> **Scope note.** This spec builds on the settings spec (#20) and does not re-specify config storage, propose/apply, timelock, or authorization. Governance is delegated to the pluggable `Credential` (#11 / DAO #12 / Agora / multisig #11). CIP-112 (Observe Script Type) is not available on-chain today, so forwarding uses the withdraw-zero staking-validator convention.

## 2. Design choices and limitations

### Design choices

| Decision | Choice | Rationale |
|---|---|---|
| Substrate | **A settings UTxO holds the registry** | Reuses propose/apply + timelock + pluggable auth unchanged (#20). |
| Registry shape | **`Map<own_hash, delegate_hash>`** | One instance governs many protocols; the immutable key is the stable identity. |
| Forced forwarding | **Every path forwards via withdraw-zero** | The only way to keep the address stable and funds in place. |
| Opt-in consent | **Enforced natively in V1** | A malicious registry repoint can change migration rules but never move funds without the user's signature. |
| Forwarding check | **Exact script hash invoked as a withdrawal** | O(1), NFT-authenticated, not spoofable. |
| Logic/migration scope | **Validate every forwarded input** | Prevents validating a benign input while another is drained. |
| Registry datum | **Any `Data`; consumers decode** | The reference settings validator accepts any value; `decode_registry` rejects a malformed registry at spend time. |

### Limitations

The reference predicates delegate the *meaning* of a forwarder's state and of a migration to the protocol's own logic / migration script; they validate only that the correct delegate runs. Nothing here validates the *content* of a protocol's logic beyond its registered hash.

## 3. Glossary

### 3.a Roles

- **Governor** (`propose_auth` / `apply_auth` of the settings instance): may stage and commit registry changes, subject to the settings timelock. Typically a DAO (#12), multisig (#11), or key.
- **User**: owner of a forwarded UTxO. For opt-in, their `Credential` must authorize a migration.
- **Logic script** (forced): the registered staking script that validates every input forwarded by a forwarder.
- **Migration script** (opt-in): the registered staking script that validates V1 → V2 moves.
- **Operator**: builds transactions (off-chain); holds no privilege beyond what it authorizes.

### 3.b Constants (validator parameters)

| Validator | Parameters | Meaning |
|---|---|---|
| Forwarder | `settings_policy`, `settings_token_name` | Locate the settings UTxO holding the registry. |
| Logic | `settings_policy`, `settings_token_name` | Same; the logic script is shared across forwarders of one settings instance. |
| V1 (opt-in) | `settings_policy`, `settings_token_name` | Same. |
| Migration | `settings_policy`, `settings_token_name`, `v2_address` | Same, plus the blessed target address. |

The **forwarder hash** is `hash(forwarder_validator(settings_policy, settings_token_name))`; likewise for the others. These hashes are the registry keys/values.

### 3.c The registry

A `Registry` is a `Map` from 28-byte script hashes to 28-byte script hashes, stored as the settings UTxO's `current` value.

- **Well-formedness.** A well-formed registry is a map from byte arrays to 28-byte script hashes whose keys are in strictly ascending byte order (so no key repeats). `decode_registry` fails on anything else; a consumer therefore rejects a malformed registry. Sorted keys let decoding run in one linear pass and lookups stop early. The reference settings validator does not constrain the shape on-chain, so writers must sort the map.
- **Authenticity.** The registry is read from the settings UTxO identified by the settings NFT (`has_nft_strict`), so it is unique and one-shot (settings spec §3.c).

### 3.d Validators

The reusable predicates and helpers, all in `onchain/lib/upgradeability/`.

**`registry`** (reading the registry, and the forwarder / V1 side):

| Function | Role |
|---|---|
| `get_registry(self, settings_policy, settings_token_name)` | Read + decode the registry from the settings reference input. |
| `lookup(registry, own_hash)` | The delegate registered for `own_hash`, if any. |
| `delegate_invoked(self, settings_policy, settings_token_name, own_hash)` | Whether the delegate registered for `own_hash` runs as a withdrawal; fails if `own_hash` is unregistered. Shared by both predicates. |
| `own_script_hash(inputs, own_ref)` | The script hash owning the input at `own_ref`. |
| `decode_registry(data)` | Decode the registry from the settings value; fails unless it is a map of byte arrays to 28-byte hashes with strictly ascending keys. |

**`delegate`** (helpers for logic and migration scripts):

| Function | Role |
|---|---|
| `Delegated { inputs, mints, withdrawals, certificates, votes }` | Every transaction item delegated to one script, by kind. |
| `delegated_items(self, registry, logic_hash)` | The items whose script credential (input address, minting policy, withdrawal or certificate credential, voter) the registry maps to `logic_hash`. |
| `delegated_to(self, settings_policy, settings_token_name, account)` | What the forced logic running as `account` must validate: `delegated_items` over the registry for its own hash. Fails if `account` is not a script or every kind is empty. |
| `forwarded_inputs(inputs, registry, logic_hash)` | Every input whose address maps to `logic_hash`. |
| `forwarded_by(self, settings_policy, settings_token_name, account)` | The inputs the opt-in migration running as `account` must validate: `forwarded_inputs` over the registry for its own hash. Fails if `account` is not a script or the set is empty. |
| `spend_redeemer(self, ref)` | The redeemer the input at `ref` was spent with, if any. How a logic script reads each forwarded input's action. |

**`credentials`** (shared by the forwarder and its delegate):

| Function | Role |
|---|---|
| `certificate_credential(certificate)` | The credential that witnesses a certificate (a stake pool's key for pool certificates). |
| `voter_credential(voter)` | The credential of a voter (a stake pool's key for a pool). |

**`forward.validate_forward(settings_policy, settings_token_name, info, self)`**, the forced forwarder, called from every purpose (one `else` handler):

Returns `True` iff `own_hash = forward.own_hash(self, info)` (the spent input's script, the minting policy, or the withdrawal, certificate or voter script credential), the registry maps `own_hash` to some `logic_hash`, and `Script(logic_hash)` is present in `self.withdrawals`. It fails for a purpose that names no script credential of its own (a key or stake pool action, or a proposal guardrail).

**`migrate.validate_upgrade(user_auth, settings_policy, settings_token_name, own_ref, self)`** — opt-in `Upgrade` path:

Returns `True` iff the registry maps `own_hash` to some `migration_hash`, `Script(migration_hash)` is present in `self.withdrawals`, **and** `user_auth` is satisfied (key in `extra_signatories`, or a script withdrawal — `authorization.is_authorized`).

The **logic** and **migration** scripts run under the withdraw-0 convention (`withdraw(redeemer, account, self)`). The forced logic validates every item of `delegated_to(self, settings_policy, settings_token_name, account)` and must reject any item kind it does not handle; the migration script validates every input of `forwarded_by(...)`. Both reject when nothing is delegated to them. Both also carry a `publish` handler, `accept_registration` (shared `withdraw_zero` module), that accepts registering their own stake credential and refuses every other certificate.

**`counter`** (helpers, non-normative demo):

| Function | Role |
|---|---|
| `state_token_name` | `"counter"`: the asset name of a forwarded counter's state token, minted under the forwarder's policy. |
| `carries_state_token(input)` | Whether the input holds exactly one state token of its own forwarder: what makes a forwarded counter genuine. |
| `validate_counter_genesis(self, policy)` | Admit a mint under `policy` only as exactly one state token paid to a fresh counter (`count: 0`, `prev_input: None`, no reference script) at `policy`'s own address. |
| `validate_counter_tick(self, own_ref)` | Settle the input at `own_ref` with a `count + 1` continuation at its own address, tagged `prev_input = own_ref`, preserving `owner` and the non-ADA assets, not decreasing lovelace, and carrying no reference script. |
| `validate_counter_migrate(self, own_ref, v2_address)` | Settle it with a state-preserving continuation at `v2_address` under the same constraints. |
| `spent_with_upgrade(self, ref)` | Whether the input at `ref` was spent with the `Upgrade` action. |
| `validate_genesis(self, policy, is_fresh)` | The genesis check for any datum shape: one state token at `policy`'s address, no reference script, an inline datum `is_fresh` accepts. |
| `settled_by(self, target_address, expected, input)` | Whether some output at `target_address` carries exactly the `expected` inline datum, no reference script, and the input's non-ADA assets. |

**`stepped_counter`** (the demo's second schema, read by `counter_logic_stepped`):

| Item | Role |
|---|---|
| `SteppedCounter` | `Unstepped { count, owner, prev_input }` (constructor 0: encodes exactly like `CounterDatum`) or `Stepped { count, owner, prev_input, step }` (constructor 1). |
| `validate_stepped_tick(self, own_ref)` | Settle the input with a `Stepped` continuation adding its step to `count`; an `Unstepped` input converts with step 1. |
| `validate_stepped_genesis(self, policy)` | Genesis of a fresh `Stepped` counter with `step > 0`; the original shape is no longer admitted. |

## 4. UTxOs

### 4.a Settings UTxO (registry)

As specified in the settings spec §4.a. Its `current` value is a well-formed registry. No other change.

### 4.b Protocol UTxO

The state a forwarder (forced) or V1 (opt-in) holds. Its shape is protocol-defined; the upgradeability predicates treat it as opaque. A forwarder address accepts payments from anyone, so a forced protocol must tell its genuine state from look-alikes paid straight to the address: the demo's forwarded counters carry one state token minted under the forwarder's own policy (created by a genesis mint the logic validates), and the logic accepts only inputs that carry it. The `counter_*` demo uses `CounterDatum { count: Int, owner: Credential, prev_input: Option<OutputReference> }`: the `prev_input` tag binds a continuation output to the UTxO it continues (`None` only at the genesis lock), so each validation settles its input by its own continuation and several UTxOs can be ticked or migrated in one transaction without one continuation swallowing another.

**Datum evolution (forced).** A forced repoint changes the logic but not the UTxOs, so their datums keep the schema they were written with. Aiken's typed decode is exact (a datum with an extra or missing field does not decode), so a new logic must decode every shape ever written on purpose. The pattern is **convert on touch**: the new logic reads the old shapes and writes only the new one on each continuation and genesis. Shapes are told apart by constructor tag: the demo's `SteppedCounter` keeps the original layout as constructor 0 (`Unstepped`), so existing counters decode unchanged, and adds `Stepped` as constructor 1.

## 5. Transactions

Throughout, `R ≜ registry(settings_ref)` is the registry read from the settings reference input, and `own_hash` is the validating script's own hash: for a spend, the payment credential of the input being validated; for the forwarder's other purposes, the script credential the purpose names (`forward.own_hash`).

### 5.a Registry change (governed, timelocked)

Identical to the settings `Propose` / `Apply` transactions (settings spec §5.b, §5.c), with the new value being a registry. The change takes effect only after `apply_delay`, and only the `apply_auth` credential can commit it. This is the **only** transaction that changes protocol behaviour.

### 5.b Forced spend (beacon indirection)

| | |
|---|---|
| **Inputs** | The forwarder UTxO (state). |
| **Reference inputs** | The settings UTxO (registry). |
| **Withdrawals** | A zero withdrawal keyed by the registered logic script's reward account. |
| **Redeemer** | Forwarder spend: any `Data` (the forwarder does not inspect it). |
| **Validation** | `validate_forward` returns `True`; the logic script independently validates every delegated item. |

The same shape covers every other use of the forwarder's credential: minting under its policy (the demo's genesis mint of a state token), withdrawing from or certifying its stake credential, or voting as it. The forwarder runs for that purpose and checks only that the logic runs; the logic validates the item or rejects it.

The forwarder's redeemer is opaque to the forwarder: all meaning lives in the logic script, selected by the registry. The logic reads each forwarded input's action with `spend_redeemer(self, input_ref)`, so a protocol with several actions is covered: one logic run validates every forwarded input, each under its own action. An **upgrade** is a §5.a registry change repointing `R[forwarder]`; no funds move.

### 5.c Opt-in upgrade (migration)

| | |
|---|---|
| **Inputs** | The user's V1 UTxO(s). |
| **Reference inputs** | The settings UTxO (registry). |
| **Withdrawals** | A zero withdrawal keyed by the registered migration script's reward account, **and** the `user_auth` credential satisfied. |
| **Outputs** | A continuation of the V1 state at `v2_address`. |
| **Redeemer** | V1 spend `Upgrade`; migration script withdrawal (opaque). |
| **Validation** | `validate_upgrade` returns `True` (consent + delegate present); the migration script checks each forwarded V1 input was spent with `Upgrade` and reappears at `v2_address`. |

An **upgrade** is: deploy V2, then a §5.a registry change setting `R[V1]` to a migration script targeting V2. Users migrate individually; V1 and V2 coexist.

## 6. Threat model

Attacks the protocol defends against, each backed by the invariants of §6.b:

- **Unauthorized repoint.** Only `propose_auth` may stage and only `apply_auth` may commit a registry change, after `apply_delay` (inherited from #20). (I1)
- **Premature repoint.** A change cannot take effect until `apply_delay` after its proposal reaches the chain. The settings validator anchors the delay on the propose transaction's validity upper bound, which a proposer cannot backdate, so not even a malicious governor can shorten it. (I2)
- **Forced drain via opt-in.** A governance repoint of a V1's migration script cannot move funds, because consent is enforced natively in V1. (I3)
- **Forwarding spoofing.** The forwarder requires the *exact* registered script hash; the hash comes from the NFT-authenticated settings UTxO and is compared by withdrawal credential, so it cannot be forged. (I4)
- **Partial forwarding validation.** A logic/migration script validates **all** items delegated to it, so a benign input cannot shield a malicious one. (I5)
- **Counterfeit state.** Anyone can pay a UTxO with a made-up datum straight to a forwarder address. The demo logic accepts only inputs carrying the forwarder's state token, so a counterfeit counter cannot be ticked as genuine. (I11)
- **Free mint through a forwarded policy.** The forwarder doubles as a minting policy, and it admits any mint once the logic runs. The logic sees every mint delegated to it (I5), and the demo admits only a single-token genesis into a fresh counter, so state tokens cannot be minted alongside a tick. (I11)
- **Unchecked purpose.** A forwarder that forwarded only its spends would let anyone mint under its policy, or withdraw, certify or vote with its credential, unchecked. It forwards every purpose, and the logic rejects item kinds it does not handle. (I4, I5)
- **Vacuous delegate.** A delegate registered under the wrong settings instance would read another instance's registry, find no inputs mapped to it, and accept over an empty set, letting every forwarder be spent unchecked. `delegated_to` and `forwarded_by` reject an empty set, so a delegate never passes without validating something. (I5)
- **Delegate deregistration.** Deregistering a delegate's stake credential would make its withdraw-0 impossible and leave every forwarder it serves (or every V1 upgrade) stuck. A delegate's `publish` handler accepts only registration, so once registered its credential cannot be deregistered or delegated. (I10)
- **Migration re-creation / double spend.** The migration script binds each forwarded input to the `Upgrade` action and a `v2_address` continuation; a UTxO is spent once, and a migrated V1 UTxO cannot be re-created under a normal action. (I6)
- **Malformed registry.** A malformed registry value makes every consumer reject (a liveness hazard), but it cannot be acted on. Governance is trusted to write well-formed maps. (I7)
- **Fake registry.** The registry is read only from the settings UTxO carrying the settings NFT; a look-alike UTxO without the NFT is not accepted. (I8)
- **Stranded state after a schema change.** Counters convert only when touched, so a logic that stops decoding a shape still held by some UTxO bricks it, and so does rolling back to a logic that cannot read the new shape. A forced logic must keep decoding every shape ever written (see §6.a). (I12)
- **Closed registry.** Closing the settings instance burns its one-shot NFT, and the instance can never be relaunched. Unlike a malformed registry, this liveness failure is **permanent**: forced forwarders reject forever and opt-in V1 UTxOs lose their only value exit. See §6.a.

### 6.a Assumptions / out of scope

- **The logic / migration script is trusted once registered.** `validate_forward` guarantees only that the registered script ran; the script itself carries the protocol's safety. For forced, a malicious repoint installs arbitrary logic — that is the inherent trust cost of beacon indirection.
- **Registry values are built for the same settings instance.** A logic or migration script must be parameterized with the settings instance whose registry points at it. The non-empty checks in `delegated_to` and `forwarded_by` stop a mismatched delegate from passing vacuously, but not a double misconfiguration in which the other instance's registry also maps an input to the same delegate.
- **Forced repoints need a sensible `apply_delay`.** The delay is the users' only window to react. The validator enforces it, but trusts the deployer to choose it: a negative or tiny delay weakens the guarantee (settings spec §6.a).
- **Delegates must be registered, and the deposit is not refunded.** A logic or migration script only runs once its stake credential is registered. Anyone may register it (the script accepts the Conway registration certificate; the older certificate needs no script approval), and since deregistration is refused, the deposit stays locked for good.
- **Closing the registry settings instance is a permanent brick.** `Close` burns the one-shot settings NFT and the instance can never be relaunched, so `get_registry` fails forever: forced forwarders become unspendable and opt-in V1 UTxOs can only tick in place (their only value exit is the migration path). A production registry must live in a settings fork without `Close`, or its governance must treat closing as forbidden (settings spec §6.a, "Closing is irreversible").
- **The reference settings validator does not constrain the registry shape.** Any `Data` is admissible; consumers reject a malformed value at spend time, but governance can still write one (a liveness, not a safety, hazard). A deployer who wants to constrain it can fork settings with their own `validate_datum`.
- **No global migration completeness.** On eUTxO each UTxO migrates independently; there is no all-or-nothing across the protocol, and no on-chain way to force a user off an opt-in V1.
- **Batched continuations are tagged.** The `counter_*` datums carry a
  `prev_input: Option<OutputReference>` tag naming the UTxO each continuation
  continues (`None` only at the genesis lock), so several UTxOs can be ticked
  or migrated in one transaction: a continuation settles only the single input
  it names, so one output cannot swallow another. A continuation must also
  carry no reference script and preserve the input's non-ADA assets exactly,
  so a permissionless tick cannot bloat the UTxO or smuggle/drop tokens.
- **Permissionless tick churn.** `Tick` needs no authorization, so anyone can
  consume and recreate a counter UTxO under the value-based rule (equal value or
  a dust top-up). The impact is UTxO contention: transactions built against the
  previous output must be rebuilt, and the churner pays the fees. The state
  itself cannot be altered or stolen (`count + 1`, the same owner and the exact
  non-ADA assets are enforced). A production protocol that cannot tolerate this
  must gate ticks with owner authorization or a schedule.
- **Continuations are existential.** `settled_by` accepts *any* matching
  continuation, so a spender who provides duplicate value can settle one input
  with more than one continuation (for example, forking the counter datum).
  Value conservation and the exact non-ADA match keep this value-backed — no
  value is created — but a protocol whose state must be unique should enforce
  uniqueness in its own logic. A forwarded demo counter is unique: its single
  state token can sit in only one output, so a forked datum without it is not
  genuine and cannot be ticked.
- **Tokenless UTxOs at a forwarder are stuck.** The demo logic rejects any forwarded input without the state token, and nothing else can spend it, so value paid straight to a forwarder address is locked for good. It was never extractable (a tick preserves value), but a production protocol may want a reclaim path in its logic.
- **A forwarder's stake credential is unusable in the demo.** The logic rejects every certificate, withdrawal and vote naming the forwarder, including the legacy registration that needs no witness, so a tick fails in a transaction that also registers the forwarder that way. A protocol that stakes through its forwarder handles these items in its logic instead.
- **Demo counters are open and permanent.** Anyone can mint a fresh counter (genesis needs no authorization), and burns are rejected, so a counter can never be closed.
- **Old datum shapes are kept, not dropped.** No on-chain check can prove that every UTxO has converted, so a forced logic should decode every shape ever written. Governance may drop an old shape only after verifying off-chain (with an indexer, at the forwarder addresses) that no UTxO still holds it, accepting that a missed one is bricked. A rollback is a schema change too: repointing to an older logic strands the counters the newer one converted, unless the older logic also reads the newer shape.
- **The protocol state's meaning is delegated.** The upgradeability predicates treat a forwarder's datum opaquely; the logic script defines it.
- **Off-chain is out of scope in this pass.**

### 6.b Invariants

- **I1 — Registry-change authorization.** `Propose` requires `propose_auth`; launch/`Apply`/`Close` require `apply_auth` (settings spec I1).
- **I2 — Timelocked effect.** A registry change is committed only when `now >= next_apply`, and its proposal wrote `next_apply >= upper + apply_delay`, so at least `apply_delay` of real time separates the proposal landing from the commit (settings spec I4).
- **I3 — Native opt-in consent.** `validate_upgrade` returns `True` only if `user_auth` is satisfied; the registered migration script cannot bypass this.
- **I4 — Forwarding integrity.** `validate_forward` returns `True` only if the exact registered delegate's withdrawal is present.
- **I5 — Full forwarded validation.** The forced logic applies its checks to every item in `delegated_to(...)` (inputs, mints, withdrawals, certificates, votes) and rejects kinds it does not handle; the migration script applies its checks to every input in `forwarded_by(...)`. Both reject when nothing is delegated.
- **I6 — Migration binding.** A migrated V1 input must have been spent with `Upgrade` and must reappear at `v2_address`.
- **I7 — Registry decodability.** A registry that is not a map of byte arrays to 28-byte hashes with strictly ascending keys is rejected by `decode_registry`; consumers never act on a malformed or ambiguous (duplicate-key) registry.
- **I8 — Registry authenticity.** The registry is read only from the settings UTxO identified by the settings NFT.
- **I10 — Delegate registration is permanent.** A logic/migration script's `publish` handler returns `True` only for `RegisterCredential`; its stake credential can be registered but never deregistered or delegated.
- **I11 — Genuine forwarded state (demo).** The counter logic ticks only inputs carrying exactly one state token of their forwarder, and admits a mint under the forwarder's policy only as one token paid to a fresh `count: 0` counter at the forwarder address.
- **I12 — Datum continuity (demo).** `counter_logic_stepped` decodes both counter shapes, writes only `Stepped`, keeps the step on every tick, and converts an `Unstepped` counter with step 1.
- **I9 — Composability.** The predicates assert only about their own credential (the input, policy, stake credential or voter they run for), the settings reference input, and the withdrawal key set (plus, for migration, the explicit `v2_address` continuation). They never assert total input/output counts, total value, or unrelated UTxOs (`ARCHITECTURE.md` §1.1).

### 6.c Completeness — when the predicates return `True` (must-accept)

> Per predicate, a **sufficient** condition Φ such that `accepts(...) ⇐ Φ`.

#### `validate_forward`

Returns `True` if **all** of:

- **F1 (own credential).** `info` names a script credential `own_hash`: for spending, the input at the spent reference exists and its payment credential is `Script(own_hash)`; for minting, the policy id; for withdrawing, publishing or voting, a `Script` credential (a certificate's own credential, a committee member or DRep voter).
- **F2 (registry).** The settings reference input exists, carries the settings NFT, and its `current` decodes to a registry `R`.
- **F3 (entry).** `R[own_hash] == Some(logic_hash)`.
- **F4 (delegate).** `Script(logic_hash)` is present in `self.withdrawals`.

#### `validate_upgrade`

Returns `True` if **all** of:

- **U1 (own input).** The input at `own_ref` exists and its payment credential is `Script(own_hash)`.
- **U2 (registry).** As F2.
- **U3 (entry).** `R[own_hash] == Some(migration_hash)`.
- **U4 (delegate).** `Script(migration_hash)` is present in `self.withdrawals`.
- **U5 (consent).** `user_auth` is satisfied: a `VerificationKey` hash in `extra_signatories`, or a `Script` credential present in `withdrawals`.

### 6.d Soundness — when the predicates return `False` (must-reject)

The predicate returns `False` (transaction rejected) whenever **any** of:

- **R1 (no/fake registry).** The settings reference input is missing, lacks the settings NFT, or its `current` is not registry-shaped. _(¬F2, ¬U2, I8)_
- **R2 (unregistered own hash).** `R[own_hash] == None`. _(¬F3, ¬U3)_
- **R3 (delegate absent).** The registered delegate's withdrawal is absent. _(¬F4, ¬U4, I4)_
- **R4 (no consent, opt-in).** `user_auth` is not satisfied. _(¬U5, I3)_

And, on the migration side (enforced by the migration script, not by `validate_upgrade`):

- **R5 (wrong action).** A forwarded V1 input was not spent with `Upgrade`. _(¬I6)_
- **R6 (no continuation / wrong target).** The migrated state does not reappear at `v2_address` with `count`, `owner` and the non-ADA assets preserved and no reference script. _(¬I6)_
- **R7 (collapsed continuation).** An input is settled by a continuation whose `prev_input` tag names another UTxO (or nothing); each validation binds the continuation by the `OutputReference` it claims, so a single output cannot satisfy two inputs.
- **R8 (bloated or altered continuation).** A continuation attaches a reference script or changes the input's non-ADA token bundle, so a permissionless tick cannot bloat the UTxO or smuggle/drop tokens.
- **R9 (vacuous delegate).** A logic or migration script runs while nothing is delegated to it under the registry it reads (for example, another settings instance's registry). _(¬I5)_
- **R11 (counterfeit or unchecked item, demo).** The counter logic rejects a delegated input without the state token, a delegated mint other than a single-token genesis into a fresh counter (including a burn), and any delegated withdrawal, certificate or vote. _(¬I5, ¬I11)_
- **R12 (no own script credential).** The forwarder runs for a purpose that names no script credential of its own (a key withdrawal, a stake pool voter or certificate, a proposal). _(¬F1)_
- **R10 (certificate other than registration).** A logic or migration script's `publish` handler runs on a deregistration, delegation, or any certificate other than `RegisterCredential`. _(¬I10)_

#### Scope of the formalization

- **The registry lookup is an axiom over `Map`.** `decode_registry` is a structural decode; its failure is a rejection.
- **The settings NFT property** (uniqueness, one-shot) is inherited from #20 and assumed.
- **The logic / migration script's own checks** are proof obligations of *those* scripts, not of these predicates.
- **Composability (I9):** soundness proofs must hold for an arbitrary number of unrelated inputs and outputs.

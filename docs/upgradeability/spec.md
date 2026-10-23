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

- **Well-formedness.** `decode_registry` fails on any value that is not a map of byte arrays to byte arrays; a consumer therefore rejects a malformed registry. The reference settings validator does not constrain the shape on-chain.
- **Authenticity.** The registry is read from the settings UTxO identified by the settings NFT (`has_nft_strict`), so it is unique and one-shot (settings spec §3.c).

### 3.d Validators

Four reusable predicates, all in `onchain/lib/upgradeability/`.

**`registry`** (helpers):

| Function | Role |
|---|---|
| `get_registry(self, settings_policy, settings_token_name)` | Read + decode the registry from the settings reference input. |
| `lookup(registry, own_hash)` | The delegate registered for `own_hash`, if any. |
| `own_script_hash(inputs, own_ref)` | The script hash owning the input at `own_ref`. |
| `forwarded_inputs(inputs, registry, logic_hash)` | Every input whose address maps to `logic_hash`. |
| `decode_registry(data)` | Decode the registry from the settings value; fails on a malformed shape. |

**`forward.validate_forward(settings_policy, settings_token_name, own_ref, self)`** — forced forwarder:

Returns `True` iff `own_hash = own_script_hash(inputs, own_ref)`, the registry maps `own_hash` to some `logic_hash`, and `Script(logic_hash)` is present in `self.withdrawals`.

**`migrate.validate_upgrade(user_auth, settings_policy, settings_token_name, own_ref, self)`** — opt-in `Upgrade` path:

Returns `True` iff the registry maps `own_hash` to some `migration_hash`, `Script(migration_hash)` is present in `self.withdrawals`, **and** `user_auth` is satisfied (key in `extra_signatories`, or a script withdrawal — `authorization.is_authorized`).

The **logic** and **migration** scripts run under the withdraw-0 convention (`withdraw(redeemer, account, self)`), derive `own_hash` from `account`, and apply their checks to `forwarded_inputs(inputs, get_registry(...), own_hash)`.

## 4. UTxOs

### 4.a Settings UTxO (registry)

As specified in the settings spec §4.a. Its `current` value is a well-formed registry. No other change.

### 4.b Protocol UTxO

The state a forwarder (forced) or V1 (opt-in) holds. Its shape is protocol-defined; the upgradeability predicates treat it as opaque. The `counter_*` demo uses `CounterDatum { count: Int, owner: Credential, prev_input: Option<OutputReference> }`: the `prev_input` tag binds a continuation output to the UTxO it continues (`None` only at the genesis lock), so each validation settles its input by its own continuation and several UTxOs can be ticked or migrated in one transaction without one continuation swallowing another.

## 5. Transactions

Throughout, `R ≜ registry(settings_ref)` is the registry read from the settings reference input, and `own_hash` is the payment credential script hash of the input being validated.

### 5.a Registry change (governed, timelocked)

Identical to the settings `Propose` / `Apply` transactions (settings spec §5.b, §5.c), with the new value being a registry. The change takes effect only after `apply_delay`, and only the `apply_auth` credential can commit it. This is the **only** transaction that changes protocol behaviour.

### 5.b Forced spend (beacon indirection)

| | |
|---|---|
| **Inputs** | The forwarder UTxO (state). |
| **Reference inputs** | The settings UTxO (registry). |
| **Withdrawals** | A zero withdrawal keyed by the registered logic script's reward account. |
| **Redeemer** | Forwarder spend: any `Data` (the forwarder does not inspect it). |
| **Validation** | `validate_forward` returns `True`; the logic script independently validates the forwarded input(s). |

The forwarder's redeemer is opaque: all meaning lives in the logic script, selected by the registry. An **upgrade** is a §5.a registry change repointing `R[forwarder]`; no funds move.

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
- **Premature repoint.** A forced change cannot take effect before the timelock elapses. (I2)
- **Forced drain via opt-in.** A governance repoint of a V1's migration script cannot move funds, because consent is enforced natively in V1. (I3)
- **Forwarding spoofing.** The forwarder requires the *exact* registered script hash; the hash comes from the NFT-authenticated settings UTxO and is compared by withdrawal credential, so it cannot be forged. (I4)
- **Partial forwarding validation.** A logic/migration script validates **all** inputs mapped to it, so a benign input cannot shield a malicious one. (I5)
- **Migration re-creation / double spend.** The migration script binds each forwarded input to the `Upgrade` action and a `v2_address` continuation; a UTxO is spent once, and a migrated V1 UTxO cannot be re-created under a normal action. (I6)
- **Malformed registry.** A malformed registry value makes every consumer reject (a liveness hazard), but it cannot be acted on. Governance is trusted to write well-formed maps. (I7)
- **Fake registry.** The registry is read only from the settings UTxO carrying the settings NFT; a look-alike UTxO without the NFT is not accepted. (I8)
- **Closed registry.** Closing the settings instance burns its one-shot NFT, and the instance can never be relaunched. Unlike a malformed registry, this liveness failure is **permanent**: forced forwarders reject forever and opt-in V1 UTxOs lose their only value exit. See §6.a.

### 6.a Assumptions / out of scope

- **The logic / migration script is trusted once registered.** `validate_forward` guarantees only that the registered script ran; the script itself carries the protocol's safety. For forced, a malicious repoint installs arbitrary logic — that is the inherent trust cost of beacon indirection.
- **Forced repoints need a timelock and bounded governance.** `apply_delay` is the users' only window to react; a negative or tiny delay, or unbounded governance, weakens the guarantee (settings spec §6.a).
- **The proposer anchors the timelock.** `next_apply = now + apply_delay` is computed from the propose transaction's lower bound, which the proposer chooses; a proposer can anchor it in the past and apply almost immediately. The delay is a scheduling tool, not a hard real-time guarantee against malicious governance (settings spec §6.a).
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
- **The protocol state's meaning is delegated.** The upgradeability predicates treat a forwarder's datum opaquely; the logic script defines it.
- **Off-chain is out of scope in this pass.**

### 6.b Invariants

- **I1 — Registry-change authorization.** `Propose` requires `propose_auth`; launch/`Apply`/`Close` require `apply_auth` (settings spec I1).
- **I2 — Timelocked effect.** A registry change is committed only when `now >= next_apply` (settings spec I4).
- **I3 — Native opt-in consent.** `validate_upgrade` returns `True` only if `user_auth` is satisfied; the registered migration script cannot bypass this.
- **I4 — Forwarding integrity.** `validate_forward` returns `True` only if the exact registered delegate's withdrawal is present.
- **I5 — Full forwarded validation.** A logic/migration script applies its checks to every input in `forwarded_inputs(...)`.
- **I6 — Migration binding.** A migrated V1 input must have been spent with `Upgrade` and must reappear at `v2_address`.
- **I7 — Registry decodability.** A registry that is not a map of byte arrays to byte arrays is rejected by `decode_registry`; consumers never act on a malformed registry.
- **I8 — Registry authenticity.** The registry is read only from the settings UTxO identified by the settings NFT.
- **I9 — Composability.** The predicates assert only about their own input, the settings reference input, and the withdrawal key set (plus, for migration, the explicit `v2_address` continuation). They never assert total input/output counts, total value, or unrelated UTxOs (`ARCHITECTURE.md` §1.1).

### 6.c Completeness — when the predicates return `True` (must-accept)

> Per predicate, a **sufficient** condition Φ such that `accepts(...) ⇐ Φ`.

#### `validate_forward`

Returns `True` if **all** of:

- **F1 (own input).** The input at `own_ref` exists and its payment credential is `Script(own_hash)`.
- **F2 (registry).** The settings reference input exists, carries the settings NFT, and its `current` decodes to a registry `R`.
- **F3 (entry).** `R[own_hash] == Some(logic_hash)`.
- **F4 (delegate).** `Script(logic_hash)` is present in `self.withdrawals`.

#### `validate_upgrade`

Returns `True` if **all** of:

- **U1 (own input).** As F1.
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
- **R6 (no continuation / wrong target).** The migrated state does not reappear at `v2_address` with the required shape. _(¬I6)_
- **R7 (collapsed continuation).** An input is settled by a continuation whose `prev_input` tag names another UTxO (or nothing); each validation binds the continuation by the `OutputReference` it claims, so a single output cannot satisfy two inputs.

#### Scope of the formalization

- **The registry lookup is an axiom over `Map`.** `decode_registry` is a structural decode; its failure is a rejection.
- **The settings NFT property** (uniqueness, one-shot) is inherited from #20 and assumed.
- **The logic / migration script's own checks** are proof obligations of *those* scripts, not of these predicates.
- **Composability (I9):** soundness proofs must hold for an arbitrary number of unrelated inputs and outputs.

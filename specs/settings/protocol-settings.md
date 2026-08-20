# Protocol Settings — Specification

> Status: Draft · Contract: `settings` · This document defines _what_ the
> contract does. The on-chain (`onchain/`) and off-chain (`offchain/`)
> implementations are correct insofar as they match this spec, not insofar as
> they match each other. See
> [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) §2.3.

## 1. Summary

A **protocol settings** instance is a single NFT-guarded UTxO holding the
**current** value of one governance-controlled parameter, as arbitrary `Data`,
together with at most one **pending change**. A change is _proposed_ by the
proposer: the pending pair `(next, next_apply)` is written with
`next_apply = now + apply_delay`. Once the delay has passed, the (separately
authorized) applier _applies_ the proposal, promoting `next` to `current`. The
instance is _launched_ by minting its NFT, which requires spending a
parameterized **seed UTxO**; because a UTxO can only be spent once, the NFT —
and therefore the settings UTxO — can never be duplicated. Closing burns the NFT
and permanently destroys the instance.

### Design choices

| Decision            | Choice                                       | Rationale                                                                                                                                                                    |
| ------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Instance identity   | **One NFT-guarded UTxO**                     | The whole state lives in one UTxO; the NFT keeps it distinguishable from any other output at the same address, and the state is always locatable by scanning for the NFT.    |
| Instance uniqueness | **One-shot mint via a seed UTxO nonce**      | Minting `+1` requires spending the parameterized `seed_utxo`. A UTxO can only be spent once, so a second launch is impossible by construction.                               |
| Change mechanism    | **Propose / delayed apply split**            | The proposer can never change `current` directly; a proposal must sit for `apply_delay` before the applier can commit it. Two credentials, two actions.                      |
| Parameter value     | **Arbitrary `Data` + `validate_datum` hook** | The validator is agnostic about what the setting _means_; a deployer-supplied predicate constrains admissible values. The reference validator ships `validate_datum = True`. |
| Authorization       | **Pluggable `Credential`**                   | `propose_auth` and `apply_auth` are `Credential`s, so a key, multisig, DAO, or smart wallet can fill either role (`ARCHITECTURE.md` §3).                                     |
| Teardown            | **Burn to close**                            | Closing burns the NFT; the seed nonce is already spent, so the instance can never be relaunched.                                                                             |

## 2. Roles

- **Proposer** (`propose_auth`): proposes a new value. Its only power is to
  write (or overwrite) the pending pair `(next, next_apply)`. It cannot apply,
  close, or touch `current`.
- **Applier** (`apply_auth`): launches the instance (mints the NFT), applies a
  pending proposal once `now >= next_apply`, and closes the instance (burns the
  NFT).
- **Consumer**: any party that reads `current` from the settings UTxO, typically
  as a reference input. Consumption is not constrained by this validator; it
  only requires the UTxO to exist.

## 3. State model

### 3.1 Script parameters

Baked into the script hash (the validator is parameterized by them):

| Parameter             | Type                | Meaning                                                                                                                                      |
| --------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `seed_utxo`           | `OutputReference`   | One-shot nonce; must be spent to mint.                                                                                                       |
| `propose_auth`        | `Credential`        | Who may `Propose`.                                                                                                                           |
| `apply_auth`          | `Credential`        | Who may launch, `Apply`, and `Close`.                                                                                                        |
| `apply_delay`         | `Int`, milliseconds | Minimum delay between a proposal's reference time and its earliest apply.                                                                    |
| `settings_token_name` | `AssetName`         | Name of the instance NFT under the script's policy.                                                                                          |
| `validate_datum`      | `fn(Data) -> Bool`  | Predicate admissible setting values must satisfy. In the reference validator it is the constant `True` (a stub to be replaced when forking). |

### 3.2 Datum (on-chain state)

Inline datum on the settings UTxO:

| Field        | Type           | Meaning                                                                |
| ------------ | -------------- | ---------------------------------------------------------------------- |
| `current`    | `Data`         | The active setting value.                                              |
| `next`       | `Option<Data>` | The proposed next value.                                               |
| `next_apply` | `Option<Int>`  | POSIX time, **milliseconds**, at or after which `next` may be applied. |

A datum is **well-formed** when `next` and `next_apply` are both `None` or both
`Some`. The actions maintain this: launch produces both `None`; `Propose`
produces both `Some`; `Apply` returns to both `None`. State transitions:

```
Mint (Launch)    ⊥  ───────────────────────────► (d, None, None)

Propose          (d, ·, ·) ────────────────────► (d, Some(d′), Some(now + apply_delay))
                                                        with d′ ≠ d and validate_datum(d′)

Apply            (d, Some(d′), Some(t)), now ≥ t ────► (d′, None, None)

Close + Burn     (·, ·, ·) ─────────────────────────► ⊥
```

### 3.3 Redeemers

**Spend** (on the settings UTxO):

| Redeemer             | Action                                                                |
| -------------------- | --------------------------------------------------------------------- |
| `Propose { out_ix }` | Proposer writes the pending pair.                                     |
| `Apply { out_ix }`   | Applier commits the pending value once the delay has passed.          |
| `Close`              | Applier closes the instance (must be accompanied by the `Burn` mint). |

**Mint** (under `policy_id`):

| Redeemer          | Action                              |
| ----------------- | ----------------------------------- |
| `Mint { out_ix }` | Launch: mint the NFT exactly once.  |
| `Burn`            | Mint-side of `Close`: burn the NFT. |

`out_ix` is the **index in the transaction's output list** of the continuation
output the redeemer identifies. The validator checks that output in full; it
never infers it.

### 3.4 Value shape

The settings UTxO's value must contain **the NFT and nothing else but ada**:
exactly `1` of `(policy_id, settings_token_name)` and no other multi-asset. This
is enforced on the launch output and on every continuation.

## 4. Action set (off-chain transaction shapes)

This is the language-agnostic interface every off-chain package implements (PRD
§6.3). "Contract input/output" means a UTxO at the settings address.

### 4.1 Launch (`Mint`)

Creates the instance by minting the NFT.

|                    |                                                                                                                                                                                                                                                                           |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inputs**         | The parameterized `seed_utxo` MUST be spent. Any wallet UTxOs for fees.                                                                                                                                                                                                   |
| **Outputs**        | One **settings output** at `out_ix`: payment credential `Script(policy_id)` (staking any), value = ada + exactly the NFT (§3.4), **inline datum**, no reference script. Datum = `SettingsDatum { current, next: None, next_apply: None }` with `validate_datum(current)`. |
| **Mint**           | Exactly one token minted under `policy_id`: `(settings_token_name, 1)`.                                                                                                                                                                                                   |
| **Redeemer**       | mint `Mint { out_ix }`.                                                                                                                                                                                                                                                   |
| **Authorization**  | `apply_auth` satisfied.                                                                                                                                                                                                                                                   |
| **Validity range** | Unconstrained.                                                                                                                                                                                                                                                            |

The seed UTxO is the one-shot guard: the minting policy equals the validator,
and minting `+1` requires the seed to be spent, so a second launch is impossible
once the seed is consumed.

### 4.2 Propose

|                    |                                                                                                                                                                                                                                                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inputs**         | The settings UTxO.                                                                                                                                                                                                                                                                                                     |
| **Outputs**        | One **continuation** at `out_ix`: address **equal to the spent input's address** (payment and staking part), value = ada + exactly the NFT, **inline datum**, no reference script. Datum = `SettingsDatum { current, next: Some(d), next_apply: Some(now + apply_delay) }` with `validate_datum(d)` and `d ≠ current`. |
| **Redeemer**       | spend `Propose { out_ix }`.                                                                                                                                                                                                                                                                                            |
| **Validity range** | Lower bound **finite**; `now` = lower bound (§5).                                                                                                                                                                                                                                                                      |
| **Authorization**  | `propose_auth` satisfied.                                                                                                                                                                                                                                                                                              |

The spent datum's `next`/`next_apply` are **ignored**: proposing always writes a
fresh pending pair and thereby supersedes any pending proposal (and resets the
apply deadline to `now + apply_delay`).

### 4.3 Apply

|                    |                                                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inputs**         | The settings UTxO, whose datum has `next = Some(d)` and `next_apply = Some(t)`.                                                                     |
| **Outputs**        | One **continuation** at `out_ix`, same form as §4.2. Datum = `SettingsDatum { current: d, next: None, next_apply: None }` with `validate_datum(d)`. |
| **Redeemer**       | spend `Apply { out_ix }`.                                                                                                                           |
| **Validity range** | Lower bound **finite** and `now >= t` (§5).                                                                                                         |
| **Authorization**  | `apply_auth` satisfied.                                                                                                                             |

### 4.4 Close

|                    |                                                                                                                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inputs**         | The settings UTxO.                                                                                                                                                                                      |
| **Outputs**        | No continuation required; the remainder (ada) may go anywhere.                                                                                                                                          |
| **Mint**           | The NFT is burned: the minted bundle under `policy_id` is exactly one pair with quantity `-1` (the spend side demands a negative quantity under the policy; the `Burn` mint side demands exactly `-1`). |
| **Redeemer**       | spend `Close` **and** mint `Burn`.                                                                                                                                                                      |
| **Authorization**  | `apply_auth` satisfied.                                                                                                                                                                                 |
| **Validity range** | Unconstrained. The datum is not read.                                                                                                                                                                   |

Closing is irreversible: the NFT is gone and the seed nonce is already spent, so
no instance can ever exist again at this script address.

## 5. Determinism & time

### 5.1 Reading "now" from the validity range

Scripts cannot read a clock; they read the transaction's validity range. The
contract uses the **lower bound** as `now` (POSIX milliseconds) for both
`Propose` and `Apply`. Because the ledger guarantees the real slot is
`>= lower bound`, requiring `now >= next_apply` guarantees the applier cannot
commit a proposal before `next_apply` has truly passed. The lower bound MUST be
finite; an unbounded-below range is rejected (there is no meaningful `now`).

### 5.2 The delay is anchored to the proposer's reference time

`next_apply = now + apply_delay` is computed from the **propose transaction's**
lower bound. The proposer chooses that bound; an honest builder sets it to the
current time, giving a real-world delay of `apply_delay`. A proposer could
anchor `now` in the past and shorten the wall-clock delay, but that is the
proposer's own scheduling choice: the proposal can never be applied earlier than
`apply_delay` after the anchor it itself declared, and only the (separately
authorized) applier can apply at all.

### 5.3 Single instance ⇒ no double-satisfaction or batching surface

Because the one-shot NFT guarantees at most one settings UTxO exists, a
transaction spends at most one contract input. There is no need for
count-preserving continuation rules (contrast
[`vesting/linear`](../vesting/linear-vesting.md) §5.1): the single continuation
identified by `out_ix` is checked in full, and merging or splitting instances is
impossible. The validator still makes no assertion about total transaction
input/output counts, so it composes freely (`ARCHITECTURE.md` §1.1).

## 6. Invariants

- **I1 — Action authorization.** `Propose` requires `propose_auth`; launch,
  `Apply`, and `Close` require `apply_auth`; the `Burn` mint runs only alongside
  `Close`.
- **I2 — Single instance.** At most one settings NFT (hence one settings UTxO)
  can ever exist: minting requires spending the one-shot `seed_utxo`, and a burn
  can never be re-minted.
- **I3 — NFT custody.** Every continuation and the launch output carry exactly
  the NFT and no other multi-asset; the NFT cannot be separated from the state,
  duplicated, or joined by smuggled tokens.
- **I4 — Delayed apply.** An `Apply` is valid only when `now >= next_apply` for
  a pending pair, so a proposal is never committed before its delay has elapsed
  relative to the proposal's reference time.
- **I5 — Datum well-formedness.** `next` and `next_apply` are always both `None`
  or both `Some`: launch and `Apply` produce the `None` pair and `Propose`
  produces the `Some` pair required by `Apply`.
- **I6 — No no-op proposals.** A `Propose` whose `d == current` is rejected; the
  setting can only be _changed_, never rewritten.
- **I7 — State integrity.** `Propose` preserves `current` and writes exactly
  `next_apply = now + apply_delay`; `Apply` promotes the pending `next` to
  `current` and clears the pair. The continuation datum must equal the expected
  one exactly.
- **I8 — Composability.** The validator asserts only about its own input, the
  seed input (at launch), the mint under its own policy, the single output named
  by `out_ix`, the validity range, and the required authorization. It never
  asserts total input/output counts or unrelated value.

## 7. Threat model & known assumptions

### Defended

- **Unauthorized propose / apply / close.** Distinct credentials per action; the
  NFT cannot be burned by anyone but the applier (with `Close`), because the NFT
  can only leave the settings UTxO by spending it, and the only redeemer that
  does not require carrying it onward is `Close`. (I1)
- **Premature apply.** `now >= next_apply` with `now` read from the validity
  lower bound (§5.1). A proposal cannot be committed before its deadline. (I4)
- **Instance duplication.** The seed nonce and the mint checks make the NFT
  one-shot: minting `+1` requires spending `seed_utxo`, which can happen once;
  the mint must be exactly one token with the parameterized name. (I2)
- **NFT detachment / state theft.** Continuations must keep the NFT at the exact
  settings address; an attacker cannot spend the settings UTxO and route the NFT
  elsewhere, nor park a "state" UTxO without it. (I3)
- **Continuation tampering.** The continuation datum must equal the expected
  `SettingsDatum` exactly: a proponent cannot rewrite `current`, and an applier
  cannot apply a different `next` than the one pending. (I7)
- **No-op proposals.** `d ≠ current` blocks propose-without-change. (I6)
- **Fake settings outputs.** The launch output's payment credential must be
  `Script(policy_id)`; continuations must reproduce the spent input's full
  address. The value checks reject outputs carrying the NFT alongside smuggled
  tokens. (I3, I8)

### Assumptions / out of scope

- **`validate_datum` is a stub** (`True`) in the reference validator. Deployers
  who care about admissible values must fork the validator to supply a real
  predicate; nothing here validates the setting's _meaning_.
- **`apply_delay` is trusted at deployment.** The reference validator does not
  constrain it (a negative delay would admit immediate applies); it is part of
  the script hash, so all parties can see it.
- **The proposer controls the delay anchor** (§5.2). `apply_delay` is the
  proposer's scheduling tool, not a hard real-time guarantee against a malicious
  proposer.
- **Closing is irreversible.** After `Close`, no instance can be relaunched at
  this script hash (seed spent, NFT burned).
- **Consumers are off-chain (or other validators).** The settings validator
  provides no read endpoint; consumers check `current` from the UTxO's datum,
  typically via a reference input (`settings/utils.get_settings_datum`).
- **Slot/ms rounding.** The ledger's lower bound is slot-granular; the validator
  interprets it in milliseconds (slot start time). Off-chain builders must
  compute `next_apply` from the same slot-start conversion (the reference
  builders do).

## 8. Completeness — when the validator returns `True` (must-accept)

> For formal verification. Per redeemer, a **sufficient** condition: a
> conjunction Φ such that `accepts(...) ⇐ Φ`. Proving it rules out _false
> negatives_ (honest spends that get stuck). It is the `⇐` direction of the
> characterization `accepts ⟺ Φ`; §9 is the `⇒` direction.
>
> Throughout, `now ≜ lower_bound(validity_range)` (§5.1) and
> `policy ≜ hash(validator params)` (§3.1). "The own input" is the contract
> input being validated.

### 8.1 `Mint { out_ix }` (Launch)

Returns `True` if **all** of:

- **M1 (mint form).** The minted bundle under `policy` consists of exactly one
  pair `(name, quantity)` with `name == settings_token_name` and
  `quantity == 1`.
- **M2 (seed spent).** `seed_utxo` is among the transaction inputs.
- **M3 (output form).** The output at `out_ix` exists; its payment credential is
  `Script(policy)`; its value contains exactly the NFT and no other multi-asset;
  its datum is **inline**; it carries no reference script.
- **M4 (initial datum).** That datum is
  `SettingsDatum { current, next: None, next_apply: None }` with
  `validate_datum(current)`.
- **M5 (auth).** `apply_auth` is satisfied (key in `extra_signatories`, or
  script invoked via a withdrawal).

### 8.2 `Propose { out_ix }`

Returns `True` if **all** of:

- **P0 (time).** The validity range has a **finite** lower bound.
- **P1 (auth).** `propose_auth` is satisfied.
- **P2 (input datum).** The spent input carries a resolvable
  `SettingsDatum { current, .. }` (its `next`/`next_apply` are unconstrained).
- **P3 (continuation form).** The output at `out_ix` exists; its address equals
  the spent input's address exactly; its value contains exactly the NFT and no
  other multi-asset; its datum is **inline**; no reference script.
- **P4 (continuation datum).** That datum is
  `SettingsDatum { current, next: Some(d), next_apply: Some(now + apply_delay) }`
  with `validate_datum(d)` and `d ≠ current`.

### 8.3 `Apply { out_ix }`

Returns `True` if **all** of:

- **A0 (time).** The validity range has a **finite** lower bound.
- **A1 (auth).** `apply_auth` is satisfied.
- **A2 (pending pair).** The spent datum is
  `SettingsDatum { next: Some(d), next_apply: Some(t), .. }`.
- **A3 (delay).** `now >= t`.
- **A4 (continuation form).** As P3.
- **A5 (continuation datum).** That datum is
  `SettingsDatum { current: d, next: None, next_apply: None }` with
  `validate_datum(d)`.

### 8.4 `Close` (with `Burn`)

Returns `True` if **all** of:

- **C1 (auth).** `apply_auth` is satisfied.
- **C2 (burn).** The minted bundle under `policy` is exactly one pair with
  `quantity == -1` (the `Burn` mint endpoint demands exactly `-1`; the `Close`
  spend endpoint demands a negative quantity under the policy).
- **C3 (own input).** The own input's payment credential is a script (its hash
  is used to look up the burn; for any spend of this validator it equals
  `policy`).

No validity-range, datum, or output constraints.

> **Boundary note.** A3 is _non-strict_: an apply whose lower bound is exactly
> `next_apply` is accepted. A formalization should model the `Apply`
> precondition as `now ≥ next_apply`, not `>`.

## 9. Soundness — when the validator returns `False` (must-reject)

> The `⇒` direction: `accepts(...) ⇒ Φ`, stated as its contrapositive so each
> clause is a separate _must-reject_ obligation. Proving these rules out _false
> positives_ (a malicious or malformed spend slipping through). Each is the
> negation of a completeness clause above; they are enumerated separately
> because each corresponds to a distinct attack.

The endpoint returns `False` (the transaction is rejected) whenever **any** of
the following holds:

- **R1 (unauthorized `Propose`).** Redeemer is `Propose` and `propose_auth` is
  **not** satisfied. _(¬P1, I1)_
- **R2 (unauthorized launch/`Apply`/`Close`).** Redeemer is `Mint`, `Apply`, or
  `Close` and `apply_auth` is **not** satisfied. _(¬M5, ¬A1, ¬C1, I1)_
- **R3 (premature apply).** Redeemer is `Apply`, the pending pair exists with
  `next_apply = Some(t)`, and `now < t` (including the unbounded-below range).
  _(¬A3, I4)_
- **R4 (apply without a pending pair).** Redeemer is `Apply` and the spent datum
  has `next = None` or `next_apply = None`. _(¬A2, I5)_
- **R5 (tampered continuation datum).** Redeemer is `Propose` or `Apply` and the
  continuation datum differs from the expected one — e.g. a changed `current` on
  propose, a different `next`, or a `next_apply ≠ now + apply_delay`. _(¬P4,
  ¬A5, I7)_
- **R6 (no-op proposal).** Redeemer is `Propose` and the proposed value equals
  `current`. _(¬P4's `d ≠ current`, I6)_
- **R7 (invalid setting value).** Redeemer is `Mint`, `Propose`, or `Apply` and
  `validate_datum` is false for the `current` (launch) or proposed `next`.
  _(¬M4, ¬P4, ¬A5)_
- **R8 (NFT detachment, duplication, or stuffing).** The launch or continuation
  output's value does not contain exactly the NFT and no other multi-asset; or
  the mint is not exactly `(settings_token_name, 1)` at launch / `-1` at close;
  or the continuation address does not match the spent input's address (launch:
  payment credential not `Script(policy)`). _(¬M1, ¬M3, ¬P3, ¬A4, ¬C2, I2, I3)_
- **R9 (non-inline datum or reference script on the output).** The launch or
  continuation output's datum is not inline, or the output carries a reference
  script. _(¬M3, ¬P3, ¬A4, §7)_
- **R10 (second launch).** Redeemer is `Mint` and `seed_utxo` is not among the
  inputs — which, once the seed is spent, is the only possible state, so a
  re-launch can never satisfy M2. _(¬M2, I2)_
- **R11 (malformed mint bundle).** The mint under `policy` does not consist of
  exactly one pair (more than one token minted/burned, or a burn with the wrong
  name/quantity). _(¬M1, ¬C2)_

### Scope of the formalization

What is an **axiom** (assumed, not proven on-chain) versus a **proof
obligation**:

- **Launch is validated on-chain** (unlike `vesting/linear`'s lock): the mint
  endpoint fully checks the initial datum and output. What is delegated is the
  _meaning_ of the setting value, via `validate_datum`, which is the constant
  `True` in the reference (§7).
- **Time is modeled as the validity lower bound** `now`, not a true clock
  (§5.1). The ledger guarantee `real_slot ≥ now` and the slot-start millisecond
  interpretation are axioms.
- **The one-shot NFT property** is a lemma about the seed nonce: inputs cannot
  be double-spent (ledger axiom), so `Mint` can pass at most once (R10).
- **Composability** (I8): the validator quantifies only over its own input, the
  seed input, its own policy's mint, and the `out_ix` output. Soundness proofs
  must therefore hold for an arbitrary number of unrelated inputs and outputs.

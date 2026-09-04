# Settings Protocol Specification

## 1. Summary

This protocol is meant to manage the settings of another (a.k.a., "main") protocol.

An instance of this protocol governs a single UTxO (called the "Settings UTxO") that, in its datum, contains the main protocol's settings. This UTxO, uniquely identified by the "Settings NFT" minted at deploy-time, contains a datum with three fields: the current settings, optionally the next settings, and optionally when the next settings will be applied if approved. 

The way it works is:

1. The _applier_ creates the first instance of the Settings protocol by minting the "Settings NFT" and locking it in the "Settings UTxO" containing the main protocol settings in its datum.
1. The main protocol consumes those settings by reading them via reference inputs.
1. A change is proposed by the _proposer_, which provides the possible next settings and when they will be applied if approved. 
1. Once the delay has passed, the _applier_ replaces the current settings with the new ones (if it chooses to accept them). Effectively changing the settings for the main protocol.
1. Once an instance of the protocol is no longer needed, the Settings UTxO can be consumed while burning the NFT permanently.

## 2. Design choices and limitations

### Design choices

| Decision            | Choice                                       | Rationale                                                                                                                                            |
| ------------------- | -------------------------------------------- | -----------------------------------------------------------------------------------------------------------------------------------------------------|
| Instance identity   | **One NFT-guarded UTxO (thread token)**      | The whole state lives in one UTxO.                                                                                                                   |
| Instance uniqueness | **One-shot mint via a seed UTxO nonce**      | Minting `+1` requires spending the parameterized `seed_utxo`. A UTxO can be spent only once, so a second instance differs by construction.           |
| Change mechanism    | **Propose / delayed apply split**            | The **proposer** can never change the settings directly. A proposal must sit _at least_ for `apply_delay` before the **applier** can commit to it.   |
| Parameter value     | **Arbitrary `Data` + `validate_datum` hook** | The validator is agnostic about what the setting contains. A deployer-supplied predicate constrains admissible values.                               |
| Authorization       | **Pluggable `Credential`**                   | `propose_auth` and `apply_auth` are flexible `Credential`s, so a key, multisig, DAO, or smart wallet can fill either role.                           |
| Teardown            | **Burn to close**                            | Closing burns the NFT. The seed nonce is already spent, so you can never relaunch the instance.                                                     |

### Limitations

The reference validator delegates the _meaning_ of the setting value to the
deployer-supplied `validate_datum` predicate (a `True` stub in the reference)
and does not constrain `apply_delay` (a negative delay would admit immediate
applies). The proposer anchors the delay, closing is irreversible, and the
staking credential is frozen at launch. The full list of assumptions and
out-of-scope items is §6.a.

## 3. Glossary

### 3.a Roles

- **Applier** (`apply_auth`): Launches the instance, applies a pending proposal once `now >= next_apply`, and closes the instance.
- **Proposer** (`propose_auth`): Proposes a new value. Its only power is to write (or overwrite) the pending pair `(next, next_apply)`. It cannot apply, close, or touch `current`.
- **Consumer**: Any party that reads `current` from the Settings UTxO as a reference input.

### 3.b Constants

Baked into the script hash (the validator is parameterized by them):

| Parameter             | Type                 | Meaning                                                                                |
| --------------------- | -------------------- | ---------------------------------------------------------------------------------------|
| `seed_utxo`           | `OutputReference`    | One-shot nonce; must be spent to mint.                                                 |
| `propose_auth`        | `Credential`         | Who may `Propose`.                                                                     |
| `apply_auth`          | `Credential`         | Who may launch, `Apply`, and `Close`.                                                  |
| `apply_delay`         | `Int` (milliseconds) | Minimum delay between when new settings are proposed and when they can be applied.     |
| `settings_token_name` | `AssetName`          | Name of the instance NFT under the script's policy.                                    |
| `validate_datum`      | `fn(Data) -> Bool`   | Predicate admissible setting values must satisfy.                                      |

The **policy id** `policy_id ≜ hash(validator params)` is the minting policy of
the Settings NFT and the payment credential of the Settings address; it is
denoted `policy` in §6.c and §6.d.

### 3.c Tokens

- **Settings NFT** — the instance token, `(policy_id, settings_token_name)`.
  - **Identity and supply.** Exactly one is minted, at deploy time, under `policy_id` with the parameterized `settings_token_name`.
  - **One-shot.** Minting `+1` requires spending the one-shot `seed_utxo`, and a burned NFT can never be re-minted, so at most one Settings NFT (hence one Settings UTxO) can ever exist. (I2)
  - **Custody.** The NFT never leaves the Settings UTxO: every continuation and the launch output carry exactly the NFT and no other multi-asset; it cannot be separated from the state, duplicated, or joined by smuggled tokens. (I3)

### 3.d Validators

One validator, parameterized by the constants of §3.b, exposing two endpoints.

**Spend** (on the Settings UTxO):

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

`out_ix` is the index of the Settings UTxO in the transaction's output list (the continuation output). The validator checks that output in full and ignores the rest. Admissible setting values are constrained by the `validate_datum` predicate (§3.b).

## 4. UTxOs

The protocol's entire on-chain state is a single UTxO.

### 4.a Settings UTxO

The Settings UTxO is uniquely identified by the Settings NFT (§3.c) and locked at the Settings address: payment credential `Script(policy_id)` (staking any). The staking credential is frozen at launch — see §6.a.

**Datum** (inline):

| Field        | Type           | Meaning                                                                     |
| ------------ | -------------- | --------------------------------------------------------------------------- |
| `current`    | `Data`         | The active setting value.                                                   |
| `next`       | `Option<Data>` | The proposed next value (if any).                                           |
| `next_apply` | `Option<Int>`  | POSIX time (milliseconds) at or after which `next` may be applied (if any). |


A datum is **well-formed** when `next` and `next_apply` are both `None` or both `Some`. The protocol checks maintain this: launch produces both `None`; `Propose` produces both `Some`; `Apply` returns both `None`. State transitions:

```
Mint (Launch)    ⊥  ─────────────────────────────────► (d, None, None)

Propose          (d, ·, ·) ──────────────────────────► (d, Some(d′), Some(now + apply_delay))
                                                            with d′ ≠ d and validate_datum(d′)

Apply            (d, Some(d′), Some(t)), now ≥ t ────► (d′, None, None)

Close + Burn     (·, ·, ·) ──────────────────────────► ⊥
```

**Value.** The Settings UTxO's value must contain **the NFT and nothing else but ADA**: exactly `1` of `(policy_id, settings_token_name)` and no other non-ADA asset. This is enforced on the launch output and on every continuation.

## 5. Transactions

All possible protocol transactions.

Scripts cannot read a clock; they read the transaction's validity range.
Throughout this section, `now` ≜ the validity range's **lower bound** (POSIX
milliseconds, slot-start interpretation — see §6.a). The lower bound MUST be
finite for `Propose` and `Apply`: an unbounded-below range is rejected (there
is no meaningful `now`). Because the ledger guarantees the real slot is
`>= lower bound`, requiring `now >= next_apply` guarantees the applier cannot
commit a proposal before `next_apply` has truly passed.

### 5.a Deploy Settings

This transaction deploys the **Settings UTxO**, which holds the main protocol parameters. The **SettingsNFT** minted from the **Settings Policy** uniquely identifies the **Settings UTxO** and validates the datum’s correctness. Other protocols will use this **Settings UTxO** as a reference input.

**Transaction overview:**

|                    |                                                                                                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Inputs**         | The parameterized `seed_utxo`. Any wallet UTxO.                                                                                                                                                  |
| **Outputs**        | One **Settings UTxO** at `out_ix`: payment credential `Script(policy_id)` (staking any), value = ADA + exactly the NFT (§4.a), **inline datum**, no reference script. Datum = `SettingsDatum { current, next: None, next_apply: None }` with `validate_datum(current)`. |
| **Mint**           | Exactly one token minted under `policy_id`: `(settings_token_name, 1)`.                                                                                                                          |
| **Redeemer**       | mint `Mint { out_ix }`.                                                                                                                                                                          |
| **Authorization**  | `apply_auth` satisfied.                                                                                                                                                                          |
| **Validity range** | Unconstrained.                                                                                                                                                                                   |

### 5.b Propose

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

### 5.c Apply

|                    |                                                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inputs**         | The settings UTxO, whose datum has `next = Some(d)` and `next_apply = Some(t)`.                                                                     |
| **Outputs**        | One **continuation** at `out_ix`, same form as §5.b. Datum = `SettingsDatum { current: d, next: None, next_apply: None }` with `validate_datum(d)`. |
| **Redeemer**       | spend `Apply { out_ix }`.                                                                                                                           |
| **Validity range** | Lower bound **finite** and `now >= t` (§5).                                                                                                         |
| **Authorization**  | `apply_auth` satisfied.                                                                                                                             |

### 5.d Close

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

## 6. Threat model

Attacks the protocol defends against, each backed by the invariants of §6.b:

- **Unauthorized propose / apply / close.** Distinct credentials per action; the
  NFT cannot be burned by anyone but the applier (with `Close`), because the NFT
  can only leave the settings UTxO by spending it, and the only redeemer that
  does not require carrying it onward is `Close`. (I1)
- **Premature apply.** `now >= next_apply` with `now` read from the validity
  lower bound (§5). A proposal cannot be committed before its deadline. (I4)
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
- **No double-satisfaction or batching surface.** The one-shot NFT guarantees
  that at most one settings UTxO exists, so a transaction spends at most one
  contract input. The single continuation identified by `out_ix` is checked in
  full, and merging or splitting instances is impossible. The validator makes no
  assertion about total transaction input/output counts. (I8)

### 6.a Assumptions / out of scope

- **`validate_datum` is a stub** (`True`) in the reference validator. Deployers
  who care about admissible values must fork the validator to supply a real
  predicate; nothing here validates the setting's _meaning_.
- **`apply_delay` is trusted at deployment.** The reference validator does not
  constrain it (a negative delay would admit immediate applies); it is part of
  the script hash, so all parties can see it.
- **The proposer controls the delay anchor.** `next_apply = now + apply_delay`
  is computed from the propose transaction's lower bound, which the proposer
  chooses (an honest builder sets it to the current time). `apply_delay` is the
  proposer's scheduling tool, not a hard real-time guarantee against a malicious
  proposer.
- **Closing is irreversible.** After `Close`, no instance can be relaunched at
  this script hash (seed spent, NFT burned).
- **The staking credential is frozen at launch.** The launch output may pick any
  staking part (§5.a), but every continuation must reproduce the spent input's
  full address. Moving the instance to a new staking key requires a fresh deployment under a new script hash.
- **Consumers are off-chain (or other validators).** The settings validator
  provides no read endpoint; consumers check `current` from the UTxO's datum,
  typically via a reference input (`settings/utils.get_settings_datum`).
- **Slot/ms rounding.** The ledger's lower bound is slot-granular; the validator
  interprets it in milliseconds (slot start time). Off-chain builders must
  compute `next_apply` from the same slot-start conversion (the reference
  builders do).

### 6.b Invariants

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

### 6.c Completeness — when the validator returns `True` (must-accept)

> For formal verification. Per redeemer, a **sufficient** condition: a
> conjunction Φ such that `accepts(...) ⇐ Φ`. Proving it rules out _false
> negatives_ (honest spends that get stuck). It is the `⇐` direction of the
> characterization `accepts ⟺ Φ`; §6.d is the `⇒` direction.
>
> Throughout, `now ≜ lower_bound(validity_range)` (§5) and
> `policy ≜ hash(validator params)` (§3.b). "The own input" is the contract
> input being validated.

#### `Mint { out_ix }` (Launch)

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

#### `Propose { out_ix }`

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

#### `Apply { out_ix }`

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

#### `Close` (with `Burn`)

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

### 6.d Soundness — when the validator returns `False` (must-reject)

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
  script. _(¬M3, ¬P3, ¬A4, §6)_
- **R10 (second launch).** Redeemer is `Mint` and `seed_utxo` is not among the
  inputs — which, once the seed is spent, is the only possible state, so a
  re-launch can never satisfy M2. _(¬M2, I2)_
- **R11 (malformed mint bundle).** The mint under `policy` does not consist of
  exactly one pair (more than one token minted/burned, or a burn with the wrong
  name/quantity). _(¬M1, ¬C2)_

#### Scope of the formalization

What is an **axiom** (assumed, not proven on-chain) versus a **proof
obligation**:

- **Launch is validated on-chain** (unlike `vesting/linear`'s lock): the mint
  endpoint fully checks the initial datum and output. What is delegated is the
  _meaning_ of the setting value, via `validate_datum`, which is the constant
  `True` in the reference (§6.a).
- **Time is modeled as the validity lower bound** `now`, not a true clock
  (§5). The ledger guarantee `real_slot ≥ now` and the slot-start millisecond
  interpretation are axioms.
- **The one-shot NFT property** is a lemma about the seed nonce: inputs cannot
  be double-spent (ledger axiom), so `Mint` can pass at most once (R10).
- **Composability** (I8): the validator quantifies only over its own input, the
  seed input, its own policy's mint, and the `out_ix` output. Soundness proofs
  must therefore hold for an arbitrary number of unrelated inputs and outputs.

# Linear Vesting — Specification

> Status: Draft · Contract: `vesting/linear` · This document defines *what* the contract does. The (`onchain/`) and off-chain (`offchain/`) implementations are correct insofar as they match this spec, not insofar as they match each other. See [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) §2.3.

## 1. Summary

A **linear vesting** instance locks a bundle of assets on behalf of a single **beneficiary** and releases it continuously between a `start_time` and an `end_time`. At any instant the beneficiary may withdraw whatever portion has vested so far; the rest stays locked under the same terms. Before `start_time` nothing is claimable; at or after `end_time` everything is. The schedule is fixed at lock time and never changes. After a configurable `recovery_time` (always strictly after `end_time`), the **locker** may recover whatever the beneficiary left unclaimed.

### Design choices

| Decision | Choice | Rationale |
|---|---|---|
| Authorization | **Pluggable `Credential`** | Both `beneficiary` and `locker` are a `Credential`, not a bare key, so a key, multisig, DAO, or smart wallet can fill either role. Exercises the experimental authorization direction of `ARCHITECTURE.md` §3 on the first contract. |
| Asset scope | **Arbitrary value bundle** | One instance can vest any mix of ada and native tokens; each asset vests on the same linear schedule. |
| Schedule | **Pure linear, no cliff** | Simplest schedule. A cliff might be a future, additive change. |
| Recovery | **Locker recovery after `recovery_time`** | Unclaimed funds are not stranded forever: past a grace time after vesting ends, the locker can reclaim them. `recovery_time` is enforced to be strictly after `end_time`, so it can never be used to claw back *unvested* funds. |
| Datum mutability | **Immutable** | Every claim derives the vested amount purely from the current time and the original totals, so partial claims never rewrite the datum. |

## 2. Roles

- **Locker** (a.k.a. grantor): creates the vesting UTxO. After `recovery_time` the locker may recover the remaining bundle (the `Cancel` action). The locker has no power over *vested* funds and cannot recover anything before `recovery_time`.
- **Beneficiary**: the party authorized to claim. Identified by a `Credential`. May be a public key (authorizes by signing) or a script (authorizes by being invoked in the claiming transaction). The beneficiary is the only party who can withdraw on the vesting schedule.

## 3. State model

### 3.1 Datum (on-chain state)

A vesting UTxO carries an **inline** datum (CIP-32; datum hashes are rejected):

| Field | Type | Meaning |
|---|---|---|
| `beneficiary` | `Credential` | Who may `Claim` starting at `start_time`. |
| `locker` | `Credential` | Who may `Cancel` after `recovery_time`. |
| `vesting` | list of `(policy_id, asset_name, total_quantity)` | The **original** locked bundle. Each entry is one asset and the total quantity that the schedule releases over its lifetime.|
| `start_time` | POSIX time, **milliseconds** | When vesting begins. |
| `end_time` | POSIX time, **milliseconds** | When vesting completes. |
| `recovery_time` | POSIX time, **milliseconds** | When the locker may recover the remainder. Must be `> end_time`. |


The datum is **immutable**: it is written once at lock time and every continuing output must reproduce it byte-for-byte.

### 3.2 Redeemer (actions on state)


| Redeemer | Action |
|---|---|
| `Claim` | Beneficiary withdraws up to the currently-vested amount. |
| `Cancel` | Locker recovers the remainder once `recovery_time` has passed. |

 
Neither redeemer carries fields; everything each needs is derivable from the transaction and the datum.

### 3.3 The vesting function

For a single asset with original total `T`, given the schedule `[start, end]` and a reference time `now`:

```
vested(T, start, end, now) =
    0                                  if now <= start
    T                                  if now >= end
    floor( T * (now - start) / (end - start) )   otherwise
```

`vested` is **monotonically non-decreasing** in `now` and is **floored**, so it never over-releases. The amount that must remain locked for that asset is `T - vested(T, start, end, now)`.

`now` is taken as the **lower bound of the transaction validity range** (see §5.2). `start_time < end_time` is required (a datum violating it is unspendable by design); `end_time < recovery_time` is additionally required for `Cancel`.

## 4. Action set (off-chain transaction shapes)

This is the language-agnostic interface every off-chain package implements (PRD §6.3). "Contract input/output" means a UTxO at the vesting script address.

### 4.1 Lock

Creates a new vesting instance. Pure off-chain construction; no script runs.

| | |
|---|---|
| **Inputs** | Any wallet UTxOs funding the bundle + fees. |
| **Outputs** | One **contract output** whose value is the bundle to vest (plus min-ada) and whose **inline datum** is the `VestingDatum` (§3.1). |
| **Redeemer** | n/a (no script executes on creation). |
| **Constraints the builder MUST uphold** | `start_time < end_time < recovery_time`; the output value contains at lest `total_quantity` of every asset listed in `vesting`; datum is inline. |


> The on-chain code does **not** validate the lock. A malformed lock could produce a UTxO whose datum does not match its value or a malformed datum (unwillingly locking the funds forever); correctness of locking is the off-chain builder's responsibility, and the §6 invariants describe what a well-formed instance looks like.

### 4.2 Claim

Withdraws the vested portion. Two cases:

**Partial claim** (`now < end_time`):

| | |
|---|---|
| **Inputs** | One or more contract inputs. Each contributes its own continuation; multiple distinct instances may be claimed in one transaction (see §5.1). Beneficiary's own UTxOs for fees. |
| **Outputs** | For each spent instance, a **continuing contract output** at the same script payment credential, with the **same datum**, holding at least `total - vested(now)` of every asset in `vesting`. If `k` spent inputs share an identical datum, the continuations carrying that datum must hold at least `k × (total - vested(now))` per asset. The claimed remainder may go anywhere (typically the beneficiary). |
| **Redeemer** | `Claim`. |
| **Validity range** | Lower bound finite and set to a time `>= start_time` for any non-zero claim. The off-chain sets the lower bound to the desired "now"; see §5.2. |
| **Authorization** | If `beneficiary` is a key: the key is in `extra_signatories`. If a script: that script is invoked via a **withdrawal** in the same transaction (withdraw-0 pattern). |


**Full claim** (`now >= end_time`):

| | |
|---|---|
| **Inputs** | One or more contract inputs. |
| **Outputs** | No continuing output required; the entire bundle may be taken. |
| **Redeemer** | `Claim`. |
| **Authorization** | As above. |

### 4.3 Cancel

Locker recovers the remaining bundle after the recovery time.

| | |
|---|---|
| **Inputs** | One or more contract inputs. Locker's own UTxOs for fees. |
| **Outputs** | No continuing output; the remainder flows to the locker. |
| **Redeemer** | `Cancel`. |
| **Validity range** | Lower bound finite and **strictly** after `recovery_time` (`now > recovery_time`). A lower bound exactly at `recovery_time` is rejected; set it to `recovery_time + 1` ms or later. |
| **Authorization** | The `locker` credential is satisfied (key signature, or script invoked), exactly as for the beneficiary in §4.2. |


## 5. Determinism & time

### 5.1 Multiple contract inputs and double satisfaction

A transaction may spend **any number** of this script's UTxOs (the contract makes no assertion about input or output counts, per `ARCHITECTURE.md` §1.1, so instances compose and batch freely). Double satisfaction is prevented without limiting inputs:

A continuation is recognized only if its inline datum is **byte-identical** to the spent input's datum, so two inputs can share one continuation only when their datums are identical. To stop that, each `Claim` input requires the continuations carrying its datum to hold `k × required`, where `k` is the number of contract inputs sharing that exact datum and `required = total - vested(now)`. All `k` inputs compute the same `k` and the same `required`, so the only way to satisfy them is to lock `k × required` in total; one shared output cannot cover several inputs. `Cancel` produces no continuation, so it has no double-satisfaction surface.

### 5.2 Reading "now" from the validity range

Scripts cannot read a clock; they read the transaction's validity range. The contract uses the **lower bound** as `now`. Because the ledger guarantees the real slot is `>= lower bound`, and `vested` is non-decreasing, using the lower bound guarantees the beneficiary can never withdraw more than has *actually* vested at inclusion time, and the locker can never `Cancel` until `recovery_time` has truly passed (the `Cancel` check requires the range to be *strictly* after `recovery_time`; see §4.3). The lower bound MUST be finite for a non-trivial claim; an unbounded-below range yields `now <= start` ⇒ zero vested.

## 6. Invariants

These hold for every valid action (`I1`–`I6`) and describe a well-formed instance (`I7`):

- **I1 — Claim authorization.** A `Claim` is valid only if the `beneficiary` credential is satisfied (key signature present, or script invoked).
- **I2 — No over-release.** After a `Claim` at reference time `now`, for every asset `(p, n, T)` in the datum, the continuations carrying that datum hold at least `k × (T - vested(T, start, end, now))`, where `k` is the number of contract inputs sharing that datum. Equivalently, no instance's cumulative removed amount can exceed `vested(...)`.
- **I3 — Schedule integrity.** A continuation reproduces the datum exactly (same beneficiary, locker, `vesting` list, `start`/`end`/`recovery`). The schedule cannot be edited mid-flight.
- **I4 — Full vesting ⇒ free.** When `now >= end_time`, the required remainder is zero, so the bundle may be fully withdrawn with no continuing output.
- **I5 — Cancel authorization & timing.** A `Cancel` is valid only if the `locker` credential is satisfied and `now > recovery_time` (strictly; the validity range must be *entirely after* `recovery_time`), with `start_time < end_time < recovery_time`. So the locker can recover only *after* full vesting plus the grace period, never *unvested* funds.
- **I6 — Composability.** The validator asserts only about its own inputs and continuing outputs (matched by credential and datum), the validity range, and the presence of the required authorization. It never asserts total transaction input/output counts or unrelated value.
- **I7 — Well-formed instance.** A correctly locked instance has an inline datum with `start_time < end_time < recovery_time` and a value covering each `(p, n, T)` with quantity `>= T`. (Off-chain responsibility; the on-chain code defends the *spending* rules regardless.)

## 7. Threat model & known assumptions

### Defended

- **Early / excessive withdrawal.** Bounded by `vested(now)` using the validity range lower bound (§5.2) and the floored vesting function, so a beneficiary cannot pull funds ahead of schedule. (I2)
- **Schedule tampering.** A continuation must reproduce the datum verbatim, so a claimer cannot shrink totals or move dates to accelerate vesting. (I3)
- **Unauthorized claim or cancel.** Pluggable credential checks: only the beneficiary can `Claim`, only the locker can `Cancel`. (I1, I5)
- **Premature recovery.** `Cancel` requires `now > recovery_time` (strictly) and the datum is checked for `end_time < recovery_time`, so a locker cannot reclaim unvested funds, even with a malformed datum. (I5)
- **Double satisfaction.** Continuations are matched by exact datum and scaled by `k`, so one output cannot satisfy several inputs. This holds even against deliberately crafted duplicate-datum instances, and without restricting input counts. (I2, §5.1)
- **Datum-hash substitution.** Only inline datums are accepted; a claim whose contract input or continuing output uses a datum hash is rejected.

### Assumptions / out of scope

- **Recovery is the only locker power.** There is no clawback of *unvested* funds and no cancel *before* `recovery_time`. If the beneficiary loses their key, funds are claimable by that (lost) credential until `recovery_time`, after which the locker can recover them.
- **Min-ada and "extra" value.** A vesting UTxO may hold ada beyond what the schedule vests (to satisfy min-ada). The contract only constrains the assets listed in `vesting`; any surplus is not schedule-protected and may be swept by the (authorized) beneficiary. Lock instances so that schedule-bearing assets are exactly the protected ones.
- **Datum/value consistency at lock time** (I7) is not enforced on-chain. An instance locked with a datum total exceeding the actual value simply becomes unclaimable for that asset until late in the schedule; it never lets the beneficiary take *more* than is present.
- **Schedule timing across identical honest instances.** The `k × required` rule keeps every instance's schedule intact even if two honestly-created instances happen to share a byte-identical datum, so no third party relying on aggregate unlock timing is affected.

## 8. Completeness — when the validator returns `True` (must-accept)

> For formal verification. This section gives, per redeemer, a **sufficient** condition: a conjunction Φ such that `accepts(tx, datum, redeemer) ⇐ Φ`. Proving it rules out *false negatives* (honest spends that get stuck, i.e. frozen funds). It is the `⇐` direction of the characterization `accepts ⟺ Φ`; §9 is the `⇒` direction.
>
> Throughout, `now ≜ lower_bound(validity_range)` (§5.2), and for a datum `d` spent by a contract input, `k` is the number of contract inputs in `tx` whose inline datum is byte-identical to `d`, and `required(p, n, T) ≜ T − vested(T, start_time, end_time, now)` for each asset `(p, n, T)` in `d.vesting`.

### 8.1 `Claim`, partial (`start_time ≤ now < end_time`)

The validator returns `True` if **all** of the following hold:

- **C0 (schedule sanity).** The datum satisfies `start_time < end_time`.
- **C1 (auth).** The `beneficiary` credential is satisfied: a verification-key beneficiary is in `extra_signatories` OR a script beneficiary is invoked via a withdrawal in `tx` (withdraw-0).
- **C2 (datum form).** The spent contract input carries an **inline** datum, and every continuing output relied on for C3/C4 carries a datum **equal** to it; which, since the input datum is inline, forces those outputs to be inline too. *(§3.1)*
- **C3 (continuation identity).** For each spent datum `d`, the continuing outputs recognized for `d` reproduce it byte-for-byte.
- **C4 (no over-release).** For each spent datum `d` and each asset `(p, n, T) ∈ d.vesting`, the continuations carrying `d` hold in aggregate `≥ k · required(p, n, T)`.
- **C5 (time read).** `validity_range` has a **finite** lower bound.

### 8.2 `Claim`, full (`now ≥ end_time`)

Returns `True` if **C0, C1, C2, C5** hold. **C3/C4 are vacuous**: `required(p, n, T) = T − T = 0` for every asset, so no continuing output is required and the entire bundle may be withdrawn. "Full" is not a distinct action, only the case of §8.1 where `vested(T, …, now) = T`.

### 8.3 `Cancel`

Returns `True` if **all** of:

- **C6 (auth).** The `locker` credential is satisfied (key signature or script invocation, exactly as C1).
- **C7 (timing).** `now > recovery_time` (**strictly**; the validity range is entirely after `recovery_time`, so an unbounded-below range is rejected). The datum must also satisfy `start_time < end_time < recovery_time`; the schedule ordering is a precondition of the action, not assumed from I7. *(I5)*
- **C8 (datum form).** The spent datum is a well-formed `VestingDatum`. `Cancel` reads no contract output, so it imposes no constraint on output datums. *(§3.1)*

`Cancel` requires **no** continuing output. *(I6, §5.1)*

> **Boundary note.** The timing check is *strict*: a lower bound exactly at `recovery_time` is rejected, so the smallest accepting `now` is `recovery_time + 1` ms. A formalization should model the `Cancel` precondition as `now > recovery_time`, not `≥`.

## 9. Soundness — when the validator returns `False` (must-reject)

> The `⇒` direction: `accepts(tx, datum, redeemer) ⇒ Φ`, stated as its contrapositive so each clause is a separate *must-reject* obligation. Proving these rules out *false positives* (a malicious or malformed spend slipping through). Each is the negation of a completeness clause above; they are enumerated separately because each corresponds to a distinct attack and is typically discharged as its own lemma.

The validator returns `False` (the spend is rejected) whenever **any** of the following holds:

- **R1 (unauthorized `Claim`).** Redeemer is `Claim` and the `beneficiary` credential is **not** satisfied. *(¬C1, I1)*
- **R2 (over-release).** Redeemer is `Claim`, `now < end_time`, and for some asset `(p, n, T)` the continuations carrying the spent datum hold `< k · required(p, n, T)`. *(¬C4, I2)*
- **R3 (schedule tampering).** Redeemer is `Claim`, `now < end_time`, and no continuing output reproduces the spent datum byte-for-byte (any change to `beneficiary`, `locker`, `vesting`, `start_time`, `end_time`, or `recovery_time`). *(¬C3, I3)*
- **R4 (datum-hash substitution).** A contract input spent under `Claim`, or a continuing output relied upon for C3/C4, uses a **datum hash** instead of an inline datum. *(¬C2, §3.1)*
- **R5 (unauthorized `Cancel`).** Redeemer is `Cancel` and the `locker` credential is **not** satisfied. *(¬C6, I5)*
- **R6 (premature recovery / malformed schedule on `Cancel`).** Redeemer is `Cancel` and `now ≤ recovery_time` (the validity range is not entirely after `recovery_time`, including the unbounded-below case), **or** the datum does not satisfy `start_time < end_time < recovery_time`. Either way the locker cannot reach *unvested* funds. *(¬C7, I5)*
- **R7 (malformed schedule on `Claim`).** Redeemer is `Claim` and the datum does not satisfy `start_time < end_time`. *(¬C0, §3.3)*

### Boundary lemmas (support R1–R6)

These are properties of `vested` and of the time read; the prover uses them to close the cases above:

- **B1 (floor).** `vested(T, start, end, now) ≤ T · (now − start) / (end − start)` and is integer-valued, so a `Claim` can never release more than the real-valued schedule. *(§3.3)*
- **B2 (monotonicity).** `vested` is non-decreasing in `now`; combined with the ledger guarantee `real_slot ≥ lower_bound`, reading `now` as the lower bound means a `Claim` never releases more than has *actually* vested at inclusion. *(§5.2)*
- **B3 (pre-start floor).** `now ≤ start_time ⇒ vested = 0 ⇒ required = T`, so an unbounded-below (or pre-start) validity range forces the full bundle to remain locked. *(§5.2)*

### Scope of the formalization

What is an **axiom** (assumed, not proven on-chain) versus a **proof obligation**:

- **Lock is not validated on-chain** (§4.1). The well-formedness of an instance (I7: `start_time < end_time < recovery_time` and value covering each `T`) is a **precondition** supplied by the off-chain builder, not a theorem about the validator. The validator's defenses (R1–R6) hold *regardless* of whether I7 was honored; a malformed instance can only become unspendable for an asset, never over-releasable (B1–B3).
- **Time is modeled as the validity lower bound** `now`, not a true clock (§5.2). The ledger guarantee `real_slot ≥ now` is an axiom.
- **Value is modeled as the per-asset `(policy_id, asset_name, quantity)` bundle** of `vesting`; surplus value (e.g. min-ada) is outside the protected set (§7, "Min-ada and extra value") and is not constrained by R2.
- **Composability** (I6): the validator quantifies only over its own inputs and the continuations matched by credential and datum, never over total `tx` input/output counts. Soundness proofs must therefore hold for an **arbitrary** number of co-spent instances and unrelated inputs/outputs (§5.1).

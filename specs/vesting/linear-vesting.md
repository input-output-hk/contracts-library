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
| **Validity range** | Lower bound finite and `>= recovery_time`. |
| **Authorization** | The `locker` credential is satisfied (key signature, or script invoked), exactly as for the beneficiary in §4.2. |


## 5. Determinism & time

### 5.1 Multiple contract inputs and double satisfaction

A transaction may spend **any number** of this script's UTxOs (the contract makes no assertion about input or output counts, per `ARCHITECTURE.md` §1.1, so instances compose and batch freely). Double satisfaction is prevented without limiting inputs:

A continuation is recognized only if its inline datum is **byte-identical** to the spent input's datum, so two inputs can share one continuation only when their datums are identical. To stop that, each `Claim` input requires the continuations carrying its datum to hold `k × required`, where `k` is the number of contract inputs sharing that exact datum and `required = total - vested(now)`. All `k` inputs compute the same `k` and the same `required`, so the only way to satisfy them is to lock `k × required` in total; one shared output cannot cover several inputs. `Cancel` produces no continuation, so it has no double-satisfaction surface.

### 5.2 Reading "now" from the validity range

Scripts cannot read a clock; they read the transaction's validity range. The contract uses the **lower bound** as `now`. Because the ledger guarantees the real slot is `>= lower bound`, and `vested` is non-decreasing, using the lower bound guarantees the beneficiary can never withdraw more than has *actually* vested at inclusion time, and the locker can never `Cancel` before `recovery_time` has truly passed. The lower bound MUST be finite for a non-trivial claim; an unbounded-below range yields `now <= start` ⇒ zero vested.

## 6. Invariants

These hold for every valid action (`I1`–`I6`) and describe a well-formed instance (`I7`):

- **I1 — Claim authorization.** A `Claim` is valid only if the `beneficiary` credential is satisfied (key signature present, or script invoked).
- **I2 — No over-release.** After a `Claim` at reference time `now`, for every asset `(p, n, T)` in the datum, the continuations carrying that datum hold at least `k × (T - vested(T, start, end, now))`, where `k` is the number of contract inputs sharing that datum. Equivalently, no instance's cumulative removed amount can exceed `vested(...)`.
- **I3 — Schedule integrity.** A continuation reproduces the datum exactly (same beneficiary, locker, `vesting` list, `start`/`end`/`recovery`). The schedule cannot be edited mid-flight.
- **I4 — Full vesting ⇒ free.** When `now >= end_time`, the required remainder is zero, so the bundle may be fully withdrawn with no continuing output.
- **I5 — Cancel authorization & timing.** A `Cancel` is valid only if the `locker` credential is satisfied and `now >= recovery_time`, with `start_time < end_time < recovery_time`. So the locker can recover only *after* full vesting plus the grace period, never *unvested* funds.
- **I6 — Composability.** The validator asserts only about its own inputs and continuing outputs (matched by credential and datum), the validity range, and the presence of the required authorization. It never asserts total transaction input/output counts or unrelated value.
- **I7 — Well-formed instance.** A correctly locked instance has an inline datum with `start_time < end_time < recovery_time` and a value covering each `(p, n, T)` with quantity `>= T`. (Off-chain responsibility; the on-chain code defends the *spending* rules regardless.)

## 7. Threat model & known assumptions

### Defended

- **Early / excessive withdrawal.** Bounded by `vested(now)` using the validity range lower bound (§5.2) and the floored vesting function, so a beneficiary cannot pull funds ahead of schedule. (I2)
- **Schedule tampering.** A continuation must reproduce the datum verbatim, so a claimer cannot shrink totals or move dates to accelerate vesting. (I3)
- **Unauthorized claim or cancel.** Pluggable credential checks: only the beneficiary can `Claim`, only the locker can `Cancel`. (I1, I5)
- **Premature recovery.** `Cancel` requires `now >= recovery_time` and the datum is checked for `end_time < recovery_time`, so a locker cannot reclaim unvested funds, even with a malformed datum. (I5)
- **Double satisfaction.** Continuations are matched by exact datum and scaled by `k`, so one output cannot satisfy several inputs. This holds even against deliberately crafted duplicate-datum instances, and without restricting input counts. (I2, §5.1)
- **Datum-hash substitution.** Only inline datums are accepted; a claim whose contract input or continuing output uses a datum hash is rejected.

### Assumptions / out of scope

- **Recovery is the only locker power.** There is no clawback of *unvested* funds and no cancel *before* `recovery_time`. If the beneficiary loses their key, funds are claimable by that (lost) credential until `recovery_time`, after which the locker can recover them.
- **Min-ada and "extra" value.** A vesting UTxO may hold ada beyond what the schedule vests (to satisfy min-ada). The contract only constrains the assets listed in `vesting`; any surplus is not schedule-protected and may be swept by the (authorized) beneficiary. Lock instances so that schedule-bearing assets are exactly the protected ones.
- **Datum/value consistency at lock time** (I7) is not enforced on-chain. An instance locked with a datum total exceeding the actual value simply becomes unclaimable for that asset until late in the schedule; it never lets the beneficiary take *more* than is present.
- **Schedule timing across identical honest instances.** The `k × required` rule keeps every instance's schedule intact even if two honestly-created instances happen to share a byte-identical datum, so no third party relying on aggregate unlock timing is affected.

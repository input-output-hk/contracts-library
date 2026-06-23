/-
Linear vesting — formal model of the schedule and proofs of its core
arithmetic properties.

This file proves the *pure-arithmetic* layer of the specification
(`../../specs/vesting/linear-vesting.md` §3.3 and the boundary lemmas
B1–B3 in §9). Those are the properties an SMT backend discharges directly.

The transaction-level properties (completeness C0–C8, soundness R1–R7) are
NOT modeled yet — they require a model of the transaction, datum, and
authorization. See README.md §Roadmap.

Proofs are written with the `blaster` tactic and require Z3 at build time.
-/
import Blaster

namespace Vesting.Linear

/-- Quantity of a single asset that has vested by `now`, given the original
total `T` and the schedule `[start, finish]`. Mirrors spec §3.3:

```
vested(T, start, end, now) =
    0                                          if now <= start
    T                                          if now >= end
    floor( T * (now - start) / (end - start) ) otherwise
```

On the domain this is used in (`0 ≤ T`, `start < finish`, and the middle
branch only when `start < now < finish`) the dividend and divisor are
non-negative, so Lean's `Int` division coincides with the spec's `floor`. -/
def vested (T start finish now : Int) : Int :=
  if now ≤ start then 0
  else if finish ≤ now then T
  else T * (now - start) / (finish - start)

/-- Remainder of one asset that must stay locked after a claim at `now`.
Spec §3.3: `T - vested(...)`. The `required(p, n, T)` of §8/§9 is this per
asset (the `k` factor lives at the transaction layer, not here). -/
def required (T start finish now : Int) : Int :=
  T - vested T start finish now

/-- **B3 (pre-start floor).** Before `start`, nothing has vested.
Spec §9 B3, §5.2. -/
theorem vested_preStart (T start finish now : Int) (h : now ≤ start) :
    vested T start finish now = 0 := by
  unfold vested
  blaster

/-- **Full vesting ⇒ free.** At or after `finish`, the whole total has
vested, so the required remainder is zero. Spec §8.2, I4. -/
theorem vested_full (T start finish now : Int)
    (hs : start < finish) (h : finish ≤ now) :
    vested T start finish now = T := by
  unfold vested
  blaster

/-- **B1 (floor / no over-release).** A claim never releases more than the
asset's total. Spec §9 B1. -/
theorem vested_le_total (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    vested T start finish now ≤ T := by
  unfold vested
  blaster

/-- The required remainder is non-negative — the dual of B1, and what makes
the §8 continuation constraint satisfiable. -/
theorem required_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ required T start finish now := by
  unfold required vested
  blaster

/-- A claim never releases a negative amount. Together with `vested_le_total`
this pins `vested` to `[0, T]`. -/
theorem vested_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ vested T start finish now := by
  unfold vested
  blaster

/-- **B2 (monotonicity).** `vested` is non-decreasing in `now`: combined with
the ledger guarantee that the real slot is ≥ the validity lower bound, this is
why reading `now` as the lower bound can never over-release. Spec §9 B2, §5.2. -/
theorem vested_mono (T start finish n₁ n₂ : Int)
    (hT : 0 ≤ T) (hs : start < finish) (h : n₁ ≤ n₂) :
    vested T start finish n₁ ≤ vested T start finish n₂ := by
  unfold vested
  blaster

end Vesting.Linear

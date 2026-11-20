import CardanoLedgerApi.V3
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Robustness

/-!
# Properties across transactions

What holds over a chain of claims on one vesting UTxO, each spending a continuation
produced by the claim before. Stated for `Spec.specAccepts`, for chains of any
length and any transactions, and proved in plain Lean, without Blaster.

- `chain_schedule_fixed`: every claim in the chain is validated under the first
  claim's datum, so the beneficiary, locker, schedule and assets never change.
- `chain_address_fixed` preserves the full vesting address.
- `chain_never_faster_than_schedule`: before the end of vesting, the funds left in
  the contract never drop below what has not yet vested, however the claims are
  split up.

Two facts about the ledger enter as assumptions, not as proofs: that each claim
spends the previous claim's continuation (`Links`), and that a claim's validity range
has started by the time it is accepted (`hnow`).

They carry over to the compiled validator for chains whose every claim lies in a
shape covered by `ClaimSound`.
-/

namespace Formal.LinearVesting.MultiTx

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Value (valueOf)
open CardanoLedgerApi.V3
open Formal.LinearVesting.Spec
open Formal.LinearVesting.Robustness

/-! ## The datum encoding is injective -/

theorem credential_toData_inj {c₁ c₂ : Credential}
    (h : IsData.toData c₁ = IsData.toData c₂) : c₁ = c₂ := by
  cases c₁ <;> cases c₂ <;> simp_all [IsData.toData, CardanoLedgerApi.IsData.Class.mkDataConstr]

theorem assetData_inj {a₁ a₂ : VestedAsset} (h : assetData a₁ = assetData a₂) : a₁ = a₂ := by
  cases a₁; cases a₂; simp_all [assetData, IsData.toData]

theorem map_assetData_inj : ∀ {l₁ l₂ : List VestedAsset},
    l₁.map assetData = l₂.map assetData → l₁ = l₂
  | [], [], _ => rfl
  | [], _ :: _, h => by cases h
  | _ :: _, [], h => by cases h
  | a₁ :: t₁, a₂ :: t₂, h => by
    simp only [List.map_cons, List.cons.injEq] at h
    rw [assetData_inj h.1, map_assetData_inj h.2]

theorem datumData_inj {d₁ d₂ : VestingDatum} (h : datumData d₁ = datumData d₂) : d₁ = d₂ := by
  cases d₁; cases d₂
  simp only [datumData, Data.Constr.injEq, List.cons.injEq, Data.List.injEq, Data.I.injEq,
    true_and, and_true] at h
  obtain ⟨hb, hl, hv, hs, he, hr⟩ := h
  rw [credential_toData_inj hb, credential_toData_inj hl, map_assetData_inj hv, hs, he, hr]

/-! ## Vesting only grows with time -/

/-- With a non-negative total and `start < finish`, the vested amount never decreases
as time passes. -/
theorem vested_le_of_le {T s f n₁ n₂ : Int} (hT : 0 ≤ T) (hsf : s < f) (hn : n₁ ≤ n₂) :
    vested T s f n₁ ≤ vested T s f n₂ := by
  have hpos : 0 < f - s := by omega
  have hmidT : ∀ n, n < f → T * (n - s) / (f - s) ≤ T := by
    intro n hnf
    calc T * (n - s) / (f - s) ≤ T * (f - s) / (f - s) :=
          Int.ediv_le_ediv hpos (Int.mul_le_mul_of_nonneg_left (by omega) hT)
      _ = T := Int.mul_ediv_cancel T (by omega)
  have hmid0 : ∀ n, s < n → 0 ≤ T * (n - s) / (f - s) := fun n hn =>
    Int.ediv_nonneg (Int.mul_nonneg hT (by omega)) (by omega)
  unfold vested
  repeat' split
  all_goals first
    | omega
    | exact hmid0 _ (by omega)
    | exact hmidT _ (by omega)
    | exact Int.ediv_le_ediv hpos (Int.mul_le_mul_of_nonneg_left (by omega) hT)

/-- The required remainder never increases as time passes. -/
theorem required_le_of_le {T s f n₁ n₂ : Int} (hT : 0 ≤ T) (hsf : s < f) (hn : n₁ ≤ n₂) :
    required T s f n₂ ≤ required T s f n₁ := by
  have := vested_le_of_le hT hsf hn
  unfold required
  omega

/-! ## Chains of claims

A chain of claims on one vesting UTxO: each claim spends a continuation produced by
the previous one. That link, that the next transaction spends that output, is a
fact about the ledger, so `Links` assumes it rather than deriving it. -/

/-- One claim: the script context `ctx`, validated under datum `d`, spending the
vesting UTxO `own`, at claim time `t`. -/
structure ClaimStep where
  d   : VestingDatum
  ctx : ScriptContext
  own : TxOut
  t   : Int

/-- The spec accepts the claim, and `own` and `t` are its vesting UTxO and claim
time. -/
def ClaimStep.Accepted (s : ClaimStep) : Prop :=
  specAccepts s.d .claim s.ctx = true ∧ ownInputOf s.ctx = some s.own ∧
    claimTimeOf s.ctx = some s.t

/-- The vesting UTxO of `s'` is a continuation produced by `s`. -/
def Links (s s' : ClaimStep) : Prop :=
  s'.own ∈ continuations s.d s.own s.ctx.scriptContextTxInfo

/-- Each step's vesting UTxO is a continuation produced by the step before. -/
def Linked : List ClaimStep → Prop
  | [] => True
  | [_] => True
  | s :: s' :: rest => Links s s' ∧ Linked (s' :: rest)

/-- A chain of accepted claims, each spending a continuation of the one before. -/
def ClaimChain (steps : List ClaimStep) : Prop :=
  Linked steps ∧ ∀ s ∈ steps, s.Accepted

/-- A claim that spends a continuation of an accepted claim is validated under the
same datum. -/
theorem link_datum_fixed {s s' : ClaimStep} (hl : Links s s') (h' : s'.Accepted) :
    s'.d = s.d := by
  have hcont := (List.mem_filter.mp hl).2
  simp only [isContinuation, Bool.and_eq_true, beq_iff_eq] at hcont
  obtain ⟨own'', hown'', hd'⟩ := claim_requires_inline_datum h'.1
  rw [h'.2.1] at hown''; cases hown''
  rw [hcont.2] at hd'
  injection hd' with hd'
  exact (datumData_inj hd').symm

/-- A claim spending a continuation uses the same full address. -/
theorem link_address_fixed {s s' : ClaimStep} (hl : Links s s') :
    s'.own.txOutAddress = s.own.txOutAddress := by
  have hcont := (List.mem_filter.mp hl).2
  simp only [isContinuation, Bool.and_eq_true, beq_iff_eq] at hcont
  exact hcont.1

/-- I3, over a whole chain: every claim in a chain of claims is validated under the
datum of the first, so the beneficiary, locker, schedule and vested assets never
change. -/
theorem chain_schedule_fixed {s₀ : ClaimStep} {rest : List ClaimStep}
    (h : ClaimChain (s₀ :: rest)) : ∀ s ∈ s₀ :: rest, s.d = s₀.d := by
  induction rest generalizing s₀ with
  | nil => intro s hs; simp at hs; rw [hs]
  | cons s₁ rest ih =>
    obtain ⟨hchain, hacc⟩ := h
    have h₁ : s₁.d = s₀.d := link_datum_fixed hchain.1 (hacc s₁ (by simp))
    have ih' := ih ⟨hchain.2, fun s hs => hacc s (by simp [hs])⟩
    intro s hs
    rcases List.mem_cons.mp hs with rfl | hs
    · rfl
    · rw [ih' s hs, h₁]

/-- Every vesting UTxO in a chain of claims sits at the same full address as
the first. -/
theorem chain_address_fixed {s₀ : ClaimStep} {rest : List ClaimStep}
    (h : ClaimChain (s₀ :: rest)) :
    ∀ s ∈ s₀ :: rest, s.own.txOutAddress = s₀.own.txOutAddress := by
  induction rest generalizing s₀ with
  | nil => intro s hs; simp at hs; rw [hs]
  | cons s₁ rest ih =>
    obtain ⟨hchain, hacc⟩ := h
    have h₁ := link_address_fixed hchain.1
    have ih' := ih ⟨hchain.2, fun s hs => hacc s (by simp [hs])⟩
    intro s hs
    rcases List.mem_cons.mp hs with rfl | hs
    · rfl
    · rw [ih' s hs, h₁]

/-- **Never faster than the schedule.** Take any chain of claims, and any moment
`now` at or after a claim's time (the ledger only accepts a transaction once its
validity range has started). If that claim happens before the end of vesting, then
each continuation it produces still holds, of every vested asset, at least what has
not vested by `now`, under the schedule set by the first claim's datum. So however
the claims are split up, no more than the vested amount ever leaves.

Assumes the vested totals are non-negative. -/
theorem chain_never_faster_than_schedule {s₀ : ClaimStep} {rest : List ClaimStep}
    (h : ClaimChain (s₀ :: rest))
    (htot : ∀ a ∈ s₀.d.vesting, 0 ≤ a.total)
    {s : ClaimStep} (hs : s ∈ s₀ :: rest) (hbefore : s.t < s₀.d.endTime)
    {now : Int} (hnow : s.t ≤ now) :
    ∀ o ∈ continuations s.d s.own s.ctx.scriptContextTxInfo, ∀ a ∈ s₀.d.vesting,
      valueOf a.policy a.name o.txOutValue
        ≥ required a.total s₀.d.startTime s₀.d.endTime now := by
  have hd := chain_schedule_fixed h s hs
  have hacc := h.2 s hs
  obtain ⟨hspec, hown, ht⟩ := hacc
  have hsf : s₀.d.startTime < s₀.d.endTime := hd ▸ claim_requires_ordered_schedule hspec
  intro o ho a ha
  have hkeep := claim_requires_remainder hspec hown ht (by rw [hd]; exact hbefore) o ho a
    (by rw [hd]; exact ha)
  rw [hd] at hkeep
  exact Int.le_trans (required_le_of_le (htot a ha) hsf hnow) hkeep

end Formal.LinearVesting.MultiTx

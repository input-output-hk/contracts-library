import CardanoLedgerApi.V3
import Formal.LinearVesting.Spec

/-!
# Robustness of the spec

What `Spec.specAccepts` guarantees about every transaction it accepts, for every
script context: no list bounds, any number of inputs, outputs, signatories and
withdrawals, any values. Proved in plain Lean, without Blaster.

`ClaimAllowed` and `CancelAllowed` state, in plain terms, when a claim and a cancel are
allowed, and `claim_iff` and `cancel_iff` prove that the spec accepts exactly those.
Each robustness theorem below reads off one part of that statement as "if accepted,
then…".

These carry over to the compiled validator through `ClaimSound` and `CancelSound`,
for the transactions those cover.
-/

namespace Formal.LinearVesting.Robustness

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.V1.Time (LowerBound)
open CardanoLedgerApi.V1.Value (valueOf)
open CardanoLedgerApi.V3
open CardanoLedgerApi.V3.Contexts
open Formal.LinearVesting.Spec

/-! ## Reading the spec

The quantities `claimOk` and `cancelOk` compute, named so the theorems can talk
about them, and lemmas relating the ledger library's helpers to plain list
functions. `claimOk_eq` and `cancelOk_eq` show the names are the spec's own
definitions. -/

def isContinuation (d : VestingDatum) (own o : TxOut) : Bool :=
  o.txOutAddress.addressCredential == own.txOutAddress.addressCredential &&
  o.txOutDatum == .OutputDatum (datumData d)

def continuations (d : VestingDatum) (own : TxOut) (info : TxInfo) : List TxOut :=
  info.txInfoOutputs.filter (isContinuation d own)

def sharedInputCount (d : VestingDatum) (own : TxOut) (info : TxInfo) : Nat :=
  (info.txInfoInputs.filter (fun i => isContinuation d own i.txInInfoResolved)).length

def holdsRequired (d : VestingDatum) (now : Int) (o : TxOut) : Bool :=
  d.vesting.all (fun a =>
    valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime now)

theorem claimOk_eq (d : VestingDatum) (own : TxOut) (info : TxInfo) (now : Int) :
    claimOk d own info now =
      (decide (d.startTime < d.endTime) && authorized d.beneficiary info &&
        own.txOutDatum == .OutputDatum (datumData d) &&
        (decide (now ≥ d.endTime) ||
          (decide (sharedInputCount d own info ≤ (continuations d own info).length) &&
            (continuations d own info).all (holdsRequired d now)))) := rfl

theorem claim_accepted_inv {d : VestingDatum} {ctx : ScriptContext}
    (h : specAccepts d .claim ctx = true) :
    ∃ ref od now c own,
      ctx.scriptContextScriptInfo = .SpendingScript ref od ∧
      validityLowerBound ctx.scriptContextTxInfo.txInfoValidRange
        = some (.FiniteLowerBound now c) ∧
      resolveInput ref ctx.scriptContextTxInfo.txInfoInputs = some own ∧
      claimOk d own.txInInfoResolved ctx.scriptContextTxInfo now = true := by
  unfold specAccepts at h
  split at h
  · simp only at h
    split at h
    · split at h
      · exact ⟨_, _, _, _, _, by assumption, by assumption, by assumption, h⟩
      · simp at h
    · simp at h
  · contradiction

theorem txSignedBy_cons (pk x : PubKeyHash) (t : List PubKeyHash) (info : TxInfo) :
    txSignedBy pk { info with txInfoSignatories := x :: t }
      = (x == pk || txSignedBy pk { info with txInfoSignatories := t }) := rfl

theorem txSignedBy_eq (pk : PubKeyHash) (info : TxInfo) :
    txSignedBy pk info = info.txInfoSignatories.any (· == pk) := by
  have key : ∀ l : List PubKeyHash,
      txSignedBy pk { info with txInfoSignatories := l } = l.any (· == pk) := by
    intro l
    induction l with
    | nil => rfl
    | cons x t ih => rw [txSignedBy_cons, ih]; rfl
  simpa using key info.txInfoSignatories

theorem credentialInWithdrawals_eq (c : Credential) (w : Withdrawals) :
    credentialInWithdrawals c w = w.any (·.1 == c) := by
  induction w with
  | nil => rfl
  | cons x t ih =>
    show (x.1 == c || credentialInWithdrawals c t) = _
    rw [ih]; rfl

theorem resolveInput_cons (ref : TxOutRef) (x : TxInInfo) (t : List TxInInfo) :
    resolveInput ref (x :: t)
      = if x.txInInfoOutRef == ref then some x else resolveInput ref t := rfl

theorem resolveInput_mem {ref : TxOutRef} {l : List TxInInfo} {i : TxInInfo}
    (h : resolveInput ref l = some i) : i ∈ l := by
  induction l with
  | nil => cases h
  | cons x t ih =>
    rw [resolveInput_cons] at h
    split at h
    · cases h; simp
    · simp [ih h]

theorem claim_parts {d : VestingDatum} {ctx : ScriptContext}
    (h : specAccepts d .claim ctx = true) :
    ∃ ref od now c own,
      ctx.scriptContextScriptInfo = .SpendingScript ref od ∧
      validityLowerBound ctx.scriptContextTxInfo.txInfoValidRange
        = some (.FiniteLowerBound now c) ∧
      resolveInput ref ctx.scriptContextTxInfo.txInfoInputs = some own ∧
      d.startTime < d.endTime ∧
      authorized d.beneficiary ctx.scriptContextTxInfo = true ∧
      own.txInInfoResolved.txOutDatum = .OutputDatum (datumData d) ∧
      (d.endTime ≤ now ∨
        (sharedInputCount d own.txInInfoResolved ctx.scriptContextTxInfo
            ≤ (continuations d own.txInInfoResolved ctx.scriptContextTxInfo).length ∧
          ∀ o ∈ continuations d own.txInInfoResolved ctx.scriptContextTxInfo,
            holdsRequired d now o = true)) := by
  obtain ⟨ref, od, now, c, own, hsi, hlow, hown, hok⟩ := claim_accepted_inv h
  rw [claimOk_eq] at hok
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq,
    List.all_eq_true] at hok
  obtain ⟨⟨⟨hs, ha⟩, hd⟩, hrest⟩ := hok
  exact ⟨ref, od, now, c, own, hsi, hlow, hown, hs, ha, hd, hrest⟩

/-- Whether a validity range starting at `low` lies after the recovery time, as
`cancelOk` decides it. -/
def afterRecovery (d : VestingDatum) (low : LowerBound) : Bool :=
  match low with
  | .FiniteLowerBound t true  => d.recoveryTime < t
  | .FiniteLowerBound t false => d.recoveryTime ≤ t
  | .InfiniteLowerBound .NegInf => false
  | .InfiniteLowerBound .PosInf => true

theorem cancelOk_eq (d : VestingDatum) (info : TxInfo) (low : LowerBound) :
    cancelOk d info low =
      (decide (d.startTime < d.endTime) && decide (d.endTime < d.recoveryTime) &&
        authorized d.locker info && afterRecovery d low) := rfl

theorem cancel_parts {d : VestingDatum} {ctx : ScriptContext}
    (h : specAccepts d .cancel ctx = true) :
    ∃ ref od low,
      ctx.scriptContextScriptInfo = .SpendingScript ref od ∧
      validityLowerBound ctx.scriptContextTxInfo.txInfoValidRange = some low ∧
      d.startTime < d.endTime ∧ d.endTime < d.recoveryTime ∧
      authorized d.locker ctx.scriptContextTxInfo = true ∧
      afterRecovery d low = true := by
  unfold specAccepts at h
  split at h
  · contradiction
  · simp only at h
    split at h
    · rw [cancelOk_eq] at h
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      obtain ⟨⟨⟨hs, he⟩, ha⟩, hr⟩ := h
      exact ⟨_, _, _, by assumption, by assumption, hs, he, ha, hr⟩
    · simp at h

/-- The spent input always counts towards `sharedInputCount`, once its datum is
the inline vesting datum. -/
theorem sharedInputCount_pos {d : VestingDatum} {info : TxInfo} {own : TxInInfo}
    (hmem : own ∈ info.txInfoInputs)
    (hd : own.txInInfoResolved.txOutDatum = .OutputDatum (datumData d)) :
    0 < sharedInputCount d own.txInInfoResolved info :=
  List.length_pos_of_mem (List.mem_filter.mpr ⟨hmem, by simp [isContinuation, hd]⟩)

/-! ## The parts of a transaction the theorems refer to -/

/-- The vesting UTxO this script is validating, if the script is spending one that
is among the inputs. -/
def ownInputOf (ctx : ScriptContext) : Option TxOut :=
  match ctx.scriptContextScriptInfo with
  | .SpendingScript ref _ =>
      (resolveInput ref ctx.scriptContextTxInfo.txInfoInputs).map (·.txInInfoResolved)
  | _ => none

/-- The lower bound of the validity range, if the range decodes. -/
def lowerBoundOf (ctx : ScriptContext) : Option LowerBound :=
  validityLowerBound ctx.scriptContextTxInfo.txInfoValidRange

/-- The claim time: the validity range's lower bound, when it is finite. -/
def claimTimeOf (ctx : ScriptContext) : Option Int :=
  match lowerBoundOf ctx with
  | some (.FiniteLowerBound t _) => some t
  | _ => none

/-- A credential has authorized the transaction: a key by signing it, a script by a
withdrawal keyed by it. -/
def AuthorizedBy (c : Credential) (info : TxInfo) : Prop :=
  match c with
  | .PubKeyCredential k => k ∈ info.txInfoSignatories
  | .ScriptCredential s => ∃ p ∈ info.txInfoWdrl, p.1 = .ScriptCredential s

theorem authorized_iff (c : Credential) (info : TxInfo) :
    authorized c info = true ↔ AuthorizedBy c info := by
  cases c with
  | PubKeyCredential k =>
    simp only [authorized, AuthorizedBy, txSignedBy_eq, List.any_eq_true, beq_iff_eq]
    exact ⟨fun ⟨x, hx, he⟩ => he ▸ hx, fun h => ⟨k, h, rfl⟩⟩
  | ScriptCredential s =>
    simp only [authorized, AuthorizedBy, credentialInWithdrawals_eq, List.any_eq_true,
      beq_iff_eq]

theorem ownInputOf_eq_some {ctx : ScriptContext} {own : TxOut}
    (h : ownInputOf ctx = some own) :
    ∃ ref od i, ctx.scriptContextScriptInfo = .SpendingScript ref od ∧
      resolveInput ref ctx.scriptContextTxInfo.txInfoInputs = some i ∧
      i.txInInfoResolved = own := by
  unfold ownInputOf at h
  split at h
  · rename_i ref od hsi
    cases hres : resolveInput ref ctx.scriptContextTxInfo.txInfoInputs with
    | none => rw [hres] at h; cases h
    | some i => rw [hres] at h; cases h; exact ⟨ref, od, i, hsi, hres, rfl⟩
  · cases h

theorem claimTimeOf_eq_some {ctx : ScriptContext} {t : Int}
    (h : claimTimeOf ctx = some t) :
    ∃ c, lowerBoundOf ctx = some (.FiniteLowerBound t c) := by
  unfold claimTimeOf at h
  split at h
  · rename_i t' c hl; cases h; exact ⟨c, hl⟩
  · cases h

/-! ## What the spec accepts -/

/-- A claim is allowed when:
- the script is spending a vesting UTxO among the inputs, carrying the datum inline;
- the validity range has a finite lower bound, the claim time;
- the schedule starts before it ends;
- the beneficiary has authorized the transaction;
- and either the claim time is at or after the end of vesting, or there are at least
  as many continuations as vesting inputs sharing the datum, each keeping the
  required remainder of every vested asset. -/
def ClaimAllowed (d : VestingDatum) (ctx : ScriptContext) : Prop :=
  ∃ own t, ownInputOf ctx = some own ∧ claimTimeOf ctx = some t ∧
    d.startTime < d.endTime ∧
    AuthorizedBy d.beneficiary ctx.scriptContextTxInfo ∧
    own.txOutDatum = .OutputDatum (datumData d) ∧
    (d.endTime ≤ t ∨
      (sharedInputCount d own ctx.scriptContextTxInfo
          ≤ (continuations d own ctx.scriptContextTxInfo).length ∧
        ∀ o ∈ continuations d own ctx.scriptContextTxInfo, ∀ a ∈ d.vesting,
          valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime t))

/-- A cancel is allowed when the script is spending a UTxO, the schedule is ordered
`start < end < recovery`, the locker has authorized the transaction, and the
validity range lies after the recovery time. -/
def CancelAllowed (d : VestingDatum) (ctx : ScriptContext) : Prop :=
  (∃ ref od, ctx.scriptContextScriptInfo = .SpendingScript ref od) ∧
  d.startTime < d.endTime ∧ d.endTime < d.recoveryTime ∧
  AuthorizedBy d.locker ctx.scriptContextTxInfo ∧
  ∃ low, lowerBoundOf ctx = some low ∧ afterRecovery d low = true

theorem holdsRequired_iff (d : VestingDatum) (t : Int) (o : TxOut) :
    holdsRequired d t o = true ↔
      ∀ a ∈ d.vesting,
        valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime t := by
  simp [holdsRequired, List.all_eq_true]

/-- The spec accepts a claim exactly when it is allowed. -/
theorem claim_iff (d : VestingDatum) (ctx : ScriptContext) :
    specAccepts d .claim ctx = true ↔ ClaimAllowed d ctx := by
  constructor
  · intro h
    obtain ⟨ref, od, t, c, i, hsi, hlow, hres, hs, ha, hd, hrest⟩ := claim_parts h
    refine ⟨i.txInInfoResolved, t, ?_, ?_, hs, (authorized_iff _ _).mp ha, hd, ?_⟩
    · simp [ownInputOf, hsi, hres]
    · simp [claimTimeOf, lowerBoundOf, hlow]
    · rcases hrest with h1 | ⟨h2, h3⟩
      · exact Or.inl h1
      · exact Or.inr ⟨h2, fun o ho => (holdsRequired_iff d t o).mp (h3 o ho)⟩
  · rintro ⟨own, t, hown, ht, hs, ha, hd, hrest⟩
    obtain ⟨ref, od, i, hsi, hres, rfl⟩ := ownInputOf_eq_some hown
    obtain ⟨c, hlow⟩ := claimTimeOf_eq_some ht
    unfold lowerBoundOf at hlow
    simp only [specAccepts, hsi, hlow, hres]
    rw [claimOk_eq]
    simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq,
      List.all_eq_true]
    refine ⟨⟨⟨hs, (authorized_iff _ _).mpr ha⟩, hd⟩, ?_⟩
    rcases hrest with h1 | ⟨h2, h3⟩
    · exact Or.inl h1
    · exact Or.inr ⟨h2, fun o ho => (holdsRequired_iff d t o).mpr (h3 o ho)⟩

/-- The spec accepts a cancel exactly when it is allowed. -/
theorem cancel_iff (d : VestingDatum) (ctx : ScriptContext) :
    specAccepts d .cancel ctx = true ↔ CancelAllowed d ctx := by
  constructor
  · intro h
    obtain ⟨ref, od, low, hsi, hlow, hs, he, ha, hr⟩ := cancel_parts h
    exact ⟨⟨ref, od, hsi⟩, hs, he, (authorized_iff _ _).mp ha, low, hlow, hr⟩
  · rintro ⟨⟨ref, od, hsi⟩, hs, he, ha, low, hlow, hr⟩
    unfold lowerBoundOf at hlow
    simp only [specAccepts, hsi, hlow]
    rw [cancelOk_eq]
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    exact ⟨⟨⟨hs, he⟩, (authorized_iff _ _).mpr ha⟩, hr⟩

/-! ## Claims

Each theorem: if the spec accepts a claim, then … -/

section Claim
variable {d : VestingDatum} {ctx : ScriptContext}

/-- R1: an accepted claim was authorized by the beneficiary: signed by it if it is a
key, or with a withdrawal keyed by it if it is a script. -/
theorem claim_requires_authorization (h : specAccepts d .claim ctx = true) :
    AuthorizedBy d.beneficiary ctx.scriptContextTxInfo := by
  obtain ⟨_, _, _, _, _, ha, _⟩ := (claim_iff d ctx).mp h
  exact ha

/-- An accepted claim's schedule starts before it ends. -/
theorem claim_requires_ordered_schedule (h : specAccepts d .claim ctx = true) :
    d.startTime < d.endTime := by
  obtain ⟨_, _, _, _, hs, _⟩ := (claim_iff d ctx).mp h
  exact hs

/-- R4: an accepted claim spends a vesting UTxO among the inputs, carrying the datum
inline, not as a hash. -/
theorem claim_requires_inline_datum (h : specAccepts d .claim ctx = true) :
    ∃ own, ownInputOf ctx = some own ∧ own.txOutDatum = .OutputDatum (datumData d) := by
  obtain ⟨own, _, hown, _, _, _, hd, _⟩ := (claim_iff d ctx).mp h
  exact ⟨own, hown, hd⟩

/-- An accepted claim's validity range has a finite lower bound: it has a claim
time. -/
theorem claim_requires_time (h : specAccepts d .claim ctx = true) :
    ∃ t, claimTimeOf ctx = some t := by
  obtain ⟨_, t, _, ht, _⟩ := (claim_iff d ctx).mp h
  exact ⟨t, ht⟩

/-- R2, I2: before the end of vesting, every continuation of an accepted claim
keeps the required remainder of every vested asset. -/
theorem claim_requires_remainder {own : TxOut} {t : Int}
    (h : specAccepts d .claim ctx = true)
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime) :
    ∀ o ∈ continuations d own ctx.scriptContextTxInfo, ∀ a ∈ d.vesting,
      valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime t := by
  obtain ⟨own', t', hown', ht', _, _, _, hrest⟩ := (claim_iff d ctx).mp h
  rw [hown] at hown'; cases hown'
  rw [ht] at ht'; cases ht'
  rcases hrest with hend | ⟨_, hkeep⟩
  · exact absurd hend (Int.not_le.mpr hbefore)
  · exact hkeep

/-- §5.1: before the end of vesting, an accepted claim has at least as many
continuations as vesting inputs sharing its datum, so one continuation cannot
satisfy two inputs. -/
theorem claim_requires_continuation_per_input {own : TxOut} {t : Int}
    (h : specAccepts d .claim ctx = true)
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime) :
    sharedInputCount d own ctx.scriptContextTxInfo
      ≤ (continuations d own ctx.scriptContextTxInfo).length := by
  obtain ⟨own', t', hown', ht', _, _, _, hrest⟩ := (claim_iff d ctx).mp h
  rw [hown] at hown'; cases hown'
  rw [ht] at ht'; cases ht'
  rcases hrest with hend | ⟨hle, _⟩
  · exact absurd hend (Int.not_le.mpr hbefore)
  · exact hle

/-- R3, I3: before the end of vesting, an accepted claim has an output at the
vesting UTxO's own address carrying the same datum inline. -/
theorem claim_requires_datum_preserved {own : TxOut} {t : Int}
    (h : specAccepts d .claim ctx = true)
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime) :
    ∃ o ∈ ctx.scriptContextTxInfo.txInfoOutputs,
      o.txOutAddress.addressCredential = own.txOutAddress.addressCredential ∧
      o.txOutDatum = .OutputDatum (datumData d) := by
  have hle := claim_requires_continuation_per_input h hown ht hbefore
  obtain ⟨own', hown', hd'⟩ := claim_requires_inline_datum h
  rw [hown] at hown'; cases hown'
  obtain ⟨ref, od, i, _, hres, rfl⟩ := ownInputOf_eq_some hown
  have hpos := sharedInputCount_pos (resolveInput_mem hres) hd'
  obtain ⟨o, ho⟩ := List.exists_mem_of_length_pos (Nat.lt_of_lt_of_le hpos hle)
  simp only [continuations, List.mem_filter, isContinuation, Bool.and_eq_true,
    beq_iff_eq] at ho
  exact ⟨o, ho.1, ho.2.1, ho.2.2⟩

end Claim

/-! ## Cancels

Each theorem: if the spec accepts a cancel, then … -/

section Cancel
variable {d : VestingDatum} {ctx : ScriptContext}

/-- I5: an accepted cancel was authorized by the locker: signed by it if it is a key,
or with a withdrawal keyed by it if it is a script. -/
theorem cancel_requires_authorization (h : specAccepts d .cancel ctx = true) :
    AuthorizedBy d.locker ctx.scriptContextTxInfo :=
  ((cancel_iff d ctx).mp h).2.2.2.1

/-- R6: an accepted cancel's validity range lies after the recovery time. -/
theorem cancel_requires_recovery_time (h : specAccepts d .cancel ctx = true) :
    ∃ low, lowerBoundOf ctx = some low ∧ afterRecovery d low = true :=
  ((cancel_iff d ctx).mp h).2.2.2.2

/-- R6: if an accepted cancel's validity range starts, inclusively, at `t`, then `t`
is strictly after the recovery time. -/
theorem cancel_requires_recovery_time_inclusive {t : Int} (h : specAccepts d .cancel ctx = true)
    (hl : lowerBoundOf ctx = some (.FiniteLowerBound t true)) :
    d.recoveryTime < t := by
  obtain ⟨low, hl', hr⟩ := cancel_requires_recovery_time h
  rw [hl] at hl'; cases hl'
  simpa [afterRecovery] using hr

/-- An accepted cancel's schedule is ordered `start < end < recovery`. -/
theorem cancel_requires_ordered_schedule (h : specAccepts d .cancel ctx = true) :
    d.startTime < d.endTime ∧ d.endTime < d.recoveryTime :=
  ⟨((cancel_iff d ctx).mp h).2.1, ((cancel_iff d ctx).mp h).2.2.1⟩

end Cancel

/-! ## Rejections

The same guarantees, stated as the transactions the spec rejects. Each follows from
one guarantee above, so it adds no reasoning of its own. -/

section RejectClaim
variable {d : VestingDatum} {ctx : ScriptContext}

/-- R1: a claim the beneficiary has not authorized is rejected. -/
theorem reject_claim_unauthorized
    (h : ¬ AuthorizedBy d.beneficiary ctx.scriptContextTxInfo) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun ha => h (claim_requires_authorization ha)

/-- R1: a claim with a key beneficiary and no signatories is rejected. -/
theorem reject_claim_no_signatories {bh : PubKeyHash}
    (hB : d.beneficiary = .PubKeyCredential bh)
    (hs : ctx.scriptContextTxInfo.txInfoSignatories = []) :
    specAccepts d .claim ctx = false :=
  reject_claim_unauthorized (by rw [hB]; simp [AuthorizedBy, hs])

/-- R1: a claim with a key beneficiary, signed only by some other key, is rejected. -/
theorem reject_claim_wrong_signer {bh w : PubKeyHash}
    (hB : d.beneficiary = .PubKeyCredential bh)
    (hs : ctx.scriptContextTxInfo.txInfoSignatories = [w]) (hw : w ≠ bh) :
    specAccepts d .claim ctx = false :=
  reject_claim_unauthorized (by
    rw [hB]; simp only [AuthorizedBy, hs, List.mem_singleton]; exact Ne.symm hw)

/-- R1: a claim with a script beneficiary and no withdrawal keyed by it is rejected,
whatever the signatories. -/
theorem reject_claim_no_withdrawal {bs : ScriptHash}
    (hB : d.beneficiary = .ScriptCredential bs)
    (hw : ∀ p ∈ ctx.scriptContextTxInfo.txInfoWdrl, p.1 ≠ .ScriptCredential bs) :
    specAccepts d .claim ctx = false :=
  reject_claim_unauthorized (by rw [hB]; rintro ⟨p, hp, hpc⟩; exact hw p hp hpc)

/-- R2: before the end of vesting, a claim with a continuation holding less than
the required remainder of some vested asset is rejected. -/
theorem reject_claim_over_release {own o : TxOut} {t : Int} {a : VestedAsset}
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime)
    (ho : o ∈ continuations d own ctx.scriptContextTxInfo) (ha : a ∈ d.vesting)
    (hq : valueOf a.policy a.name o.txOutValue < required a.total d.startTime d.endTime t) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h =>
    absurd (claim_requires_remainder h hown ht hbefore o ho a ha) (Int.not_le.mpr hq)

/-- R3: before the end of vesting, a claim with no output at the vesting address
carrying the datum inline is rejected. -/
theorem reject_claim_datum_tamper {own : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime)
    (hno : ∀ o ∈ ctx.scriptContextTxInfo.txInfoOutputs,
      o.txOutAddress.addressCredential = own.txOutAddress.addressCredential →
        o.txOutDatum ≠ .OutputDatum (datumData d)) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h => by
    obtain ⟨o, ho, haddr, hd⟩ := claim_requires_datum_preserved h hown ht hbefore
    exact hno o ho haddr hd

/-- R4: a claim whose vesting UTxO carries a datum hash instead of an inline datum is
rejected. -/
theorem reject_claim_datum_hash {own : TxOut} {dh : DatumHash}
    (hown : ownInputOf ctx = some own) (hd : own.txOutDatum = .OutputDatumHash dh) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h => by
    obtain ⟨own', hown', hd'⟩ := claim_requires_inline_datum h
    rw [hown] at hown'; cases hown'
    rw [hd] at hd'; cases hd'

/-- §5.1, I2: before the end of vesting, a claim with fewer continuations than
vesting inputs sharing its datum is rejected: one continuation cannot satisfy two
inputs. -/
theorem reject_claim_double_satisfaction {own : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime)
    (hlt : (continuations d own ctx.scriptContextTxInfo).length
      < sharedInputCount d own ctx.scriptContextTxInfo) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h =>
    absurd (claim_requires_continuation_per_input h hown ht hbefore) (Nat.not_le.mpr hlt)

/-- §5.1, C4: before the end of vesting, two vesting inputs sharing a datum with a
single continuation are rejected, however much that continuation holds. -/
theorem reject_claim_merged_instances {own : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime)
    (hk : sharedInputCount d own ctx.scriptContextTxInfo = 2)
    (hc : (continuations d own ctx.scriptContextTxInfo).length = 1) :
    specAccepts d .claim ctx = false :=
  reject_claim_double_satisfaction hown ht hbefore (by omega)

/-- §5.1, C4: before the end of vesting, a batched claim with two continuations is
rejected if either holds less than the required remainder of a vested asset,
whatever the other holds. -/
theorem reject_claim_underfunded_batch {own o₁ o₂ : TxOut} {t : Int} {a : VestedAsset}
    (hown : ownInputOf ctx = some own) (ht : claimTimeOf ctx = some t)
    (hbefore : t < d.endTime)
    (hc : continuations d own ctx.scriptContextTxInfo = [o₁, o₂]) (ha : a ∈ d.vesting)
    (hq : valueOf a.policy a.name o₁.txOutValue < required a.total d.startTime d.endTime t ∨
      valueOf a.policy a.name o₂.txOutValue < required a.total d.startTime d.endTime t) :
    specAccepts d .claim ctx = false := by
  rcases hq with hq | hq
  · exact reject_claim_over_release hown ht hbefore (by simp [hc]) ha hq
  · exact reject_claim_over_release hown ht hbefore (by simp [hc]) ha hq

/-- A claim on a schedule with `startTime ≥ endTime` is rejected. -/
theorem reject_claim_bad_schedule (hs : d.endTime ≤ d.startTime) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h => absurd hs (Int.not_le.mpr (claim_requires_ordered_schedule h))

/-- A claim with no claim time, because its validity range has no finite lower
bound or does not decode, is rejected. -/
theorem reject_claim_no_time (hn : claimTimeOf ctx = none) :
    specAccepts d .claim ctx = false :=
  Bool.eq_false_iff.mpr fun h => by
    obtain ⟨t, ht⟩ := claim_requires_time h
    rw [hn] at ht; cases ht

/-- A claim whose validity range has an infinite lower bound is rejected. -/
theorem reject_claim_infinite_lower {b : InfiniteBound}
    (hl : lowerBoundOf ctx = some (.InfiniteLowerBound b)) :
    specAccepts d .claim ctx = false :=
  reject_claim_no_time (by simp [claimTimeOf, hl])

end RejectClaim

section RejectCancel
variable {d : VestingDatum} {ctx : ScriptContext}

/-- I5: a cancel the locker has not authorized is rejected. -/
theorem reject_cancel_unauthorized (h : ¬ AuthorizedBy d.locker ctx.scriptContextTxInfo) :
    specAccepts d .cancel ctx = false :=
  Bool.eq_false_iff.mpr fun ha => h (cancel_requires_authorization ha)

/-- I5: a cancel with a key locker that has not signed is rejected. -/
theorem reject_cancel_unsigned {lk : PubKeyHash}
    (hL : d.locker = .PubKeyCredential lk)
    (hs : lk ∉ ctx.scriptContextTxInfo.txInfoSignatories) :
    specAccepts d .cancel ctx = false :=
  reject_cancel_unauthorized (by rw [hL]; exact hs)

/-- R6: a cancel whose validity range does not lie after the recovery time is
rejected. -/
theorem reject_cancel_premature {low : LowerBound}
    (hl : lowerBoundOf ctx = some low) (hr : afterRecovery d low = false) :
    specAccepts d .cancel ctx = false :=
  Bool.eq_false_iff.mpr fun h => by
    obtain ⟨low', hl', hr'⟩ := cancel_requires_recovery_time h
    rw [hl] at hl'; cases hl'
    rw [hr] at hr'; cases hr'

/-- R6: a cancel whose validity range starts, inclusively, at or before the recovery
time is rejected. -/
theorem reject_cancel_premature_inclusive {t : Int}
    (hl : lowerBoundOf ctx = some (.FiniteLowerBound t true)) (ht : t ≤ d.recoveryTime) :
    specAccepts d .cancel ctx = false :=
  reject_cancel_premature hl (by simp [afterRecovery]; omega)

/-- A cancel on a schedule not ordered `start < end < recovery` is rejected. -/
theorem reject_cancel_bad_schedule
    (hs : d.endTime ≤ d.startTime ∨ d.recoveryTime ≤ d.endTime) :
    specAccepts d .cancel ctx = false :=
  Bool.eq_false_iff.mpr fun h => by
    obtain ⟨hse, her⟩ := cancel_requires_ordered_schedule h
    rcases hs with hs | hs
    · exact absurd hs (Int.not_le.mpr hse)
    · exact absurd hs (Int.not_le.mpr her)

end RejectCancel

end Formal.LinearVesting.Robustness

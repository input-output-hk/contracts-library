import CardanoLedgerApi.V3
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Robustness

/-!
# Functionality of the spec

Which honest transactions `SpecNew.specAccepts` accepts, for every script context.
Each theorem lists, as hypotheses, what a well-formed transaction of that kind
provides, and concludes that the spec accepts it. Proved in plain Lean, without
Blaster, from `claim_iff` and `cancel_iff` in `Robustness.lean`.

These carry over to the compiled validator through `ClaimComplete` and
`CancelComplete`, for the transactions those cover.
-/

namespace Formal.LinearVesting.Functionality

open PlutusCore.Integer (Integer)
open CardanoLedgerApi.V1.Time (LowerBound)
open CardanoLedgerApi.V1.Value (valueOf)
open CardanoLedgerApi.V3
open Formal.LinearVesting.Spec
open Formal.LinearVesting.Robustness

variable {d : VestingDatum} {ctx : ScriptContext}

/-! ## Authorization -/

/-- A key has authorized a transaction it signs. -/
theorem authorizedBy_key {k : PubKeyHash} (h : k ∈ ctx.scriptContextTxInfo.txInfoSignatories) :
    AuthorizedBy (.PubKeyCredential k) ctx.scriptContextTxInfo := h

/-- A script has authorized a transaction with a withdrawal keyed by it. -/
theorem authorizedBy_script {s : ScriptHash} {amt : Integer}
    (h : ((.ScriptCredential s, amt) : Credential × Integer) ∈ ctx.scriptContextTxInfo.txInfoWdrl) :
    AuthorizedBy (.ScriptCredential s) ctx.scriptContextTxInfo :=
  ⟨_, h, rfl⟩

/-! ## Claims -/

/-- C1–C4: before the end of vesting, a claim is accepted when it spends a vesting
UTxO carrying the datum inline, on an ordered schedule, authorized by the
beneficiary, with at least as many continuations as vesting inputs sharing the
datum, each keeping the required remainder of every vested asset. -/
theorem accept_claim {own : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own)
    (hd : own.txOutDatum = .OutputDatum (datumData d))
    (ht : claimTimeOf ctx = some t)
    (hs : d.startTime < d.endTime)
    (ha : AuthorizedBy d.beneficiary ctx.scriptContextTxInfo)
    (hcount : sharedInputCount d own ctx.scriptContextTxInfo
      ≤ (continuations d own ctx.scriptContextTxInfo).length)
    (hkeep : ∀ o ∈ continuations d own ctx.scriptContextTxInfo, ∀ a ∈ d.vesting,
      valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime t) :
    specAccepts d .claim ctx = true :=
  (claim_iff d ctx).mpr ⟨own, t, hown, ht, hs, ha, hd, Or.inr ⟨hcount, hkeep⟩⟩

/-- The typical partial claim: the vesting UTxO is the only vesting input with its
datum, and the claim has exactly one continuation, which keeps the required
remainder. -/
theorem accept_claim_one_continuation {own o : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own)
    (hd : own.txOutDatum = .OutputDatum (datumData d))
    (ht : claimTimeOf ctx = some t)
    (hs : d.startTime < d.endTime)
    (ha : AuthorizedBy d.beneficiary ctx.scriptContextTxInfo)
    (hone : sharedInputCount d own ctx.scriptContextTxInfo = 1)
    (hcont : continuations d own ctx.scriptContextTxInfo = [o])
    (hkeep : ∀ a ∈ d.vesting,
      valueOf a.policy a.name o.txOutValue ≥ required a.total d.startTime d.endTime t) :
    specAccepts d .claim ctx = true :=
  accept_claim hown hd ht hs ha (by rw [hone, hcont]; simp)
    (by intro o' ho'; rw [hcont] at ho'; simp at ho'; subst ho'; exact hkeep)

/-- C5, I4: at or after the end of vesting, a claim is accepted when it spends a
vesting UTxO carrying the datum inline, on an ordered schedule, authorized by the
beneficiary, whatever its outputs. -/
theorem accept_claim_after_end {own : TxOut} {t : Int}
    (hown : ownInputOf ctx = some own)
    (hd : own.txOutDatum = .OutputDatum (datumData d))
    (ht : claimTimeOf ctx = some t)
    (hs : d.startTime < d.endTime)
    (ha : AuthorizedBy d.beneficiary ctx.scriptContextTxInfo)
    (hafter : d.endTime ≤ t) :
    specAccepts d .claim ctx = true :=
  (claim_iff d ctx).mpr ⟨own, t, hown, ht, hs, ha, hd, Or.inl hafter⟩

/-! ## Cancels -/

/-- §8.3: a cancel is accepted when the script is spending a UTxO, the schedule is
ordered `start < end < recovery`, the locker has authorized it, and the validity
range lies after the recovery time. -/
theorem accept_cancel {ref : TxOutRef} {od : Option Datum} {low : LowerBound}
    (hsi : ctx.scriptContextScriptInfo = .SpendingScript ref od)
    (hs : d.startTime < d.endTime) (he : d.endTime < d.recoveryTime)
    (ha : AuthorizedBy d.locker ctx.scriptContextTxInfo)
    (hl : lowerBoundOf ctx = some low) (hr : afterRecovery d low = true) :
    specAccepts d .cancel ctx = true :=
  (cancel_iff d ctx).mpr ⟨⟨ref, od, hsi⟩, hs, he, ha, low, hl, hr⟩

/-- The typical cancel: signed by a key locker, with a validity range starting,
inclusively, strictly after the recovery time. -/
theorem accept_cancel_key {ref : TxOutRef} {od : Option Datum} {lk : PubKeyHash} {t : Int}
    (hsi : ctx.scriptContextScriptInfo = .SpendingScript ref od)
    (hs : d.startTime < d.endTime) (he : d.endTime < d.recoveryTime)
    (hL : d.locker = .PubKeyCredential lk)
    (hsig : lk ∈ ctx.scriptContextTxInfo.txInfoSignatories)
    (hl : lowerBoundOf ctx = some (.FiniteLowerBound t true))
    (ht : d.recoveryTime < t) :
    specAccepts d .cancel ctx = true :=
  accept_cancel hsi hs he (by rw [hL]; exact hsig) hl (by simpa [afterRecovery] using ht)

end Formal.LinearVesting.Functionality

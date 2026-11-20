import Blaster
import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.TxBuilder
import Formal.LinearVesting.CancelSound
import Formal.LinearVesting.CancelComplete
import Formal.LinearVesting.ClaimSound
import Formal.LinearVesting.ClaimComplete

/-!
# Corollaries for the compiled validator

General statements about `spendValidator`, derived from the agreement theorems:
each uses a `Sound` or `Complete` theorem to replace the validator by `specAccepts`,
then checks the property of the spec alone, which runs no UPLC.

The soundness corollaries use only `ClaimSound` and `CancelSound`, so they stay valid
for an adapted validator that re-proves only those.

Each holds for the transaction shapes of `TxBuilder`, within the bounds of the
agreement theorem it uses. Fixed-value examples are in `Tests.lean`.
-/

namespace Formal.LinearVesting.Corollaries

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open PlutusCore.UPLC.Term (Program)
open CardanoLedgerApi.V1.Time (UpperBound)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash ScriptContext ScriptHash TxInfo TxOutRef)
open Formal.Shared.Common (validatorAccepts validatorRejects)
open Formal.LinearVesting.Spec
  (VestedAsset VestingDatum VestingRedeemer datumData required specAccepts)
open Formal.LinearVesting.Script (spendValidator)
open Formal.LinearVesting.TxBuilder
open Formal.LinearVesting.CancelSound (cancel_sound)
open Formal.LinearVesting.CancelComplete (cancel_complete)
open Formal.LinearVesting.ClaimSound (claim_sound claim_sound_any_out)
open Formal.LinearVesting.ClaimComplete (claim_complete claim_complete_any_out)

/-! ## Carrying results from the spec to a validator -/

/-- Where a validator is sound, whatever the spec rejects, the validator rejects. -/
theorem rejects_of_sound {v : Program} {d : VestingDatum} {r : VestingRedeemer}
    {ctx : ScriptContext} (hs : Sound v d r ctx) (h : specAccepts d r ctx = false) :
    validatorRejects ctx v := fun hacc => by
  have := hs hacc
  rw [h] at this
  cases this

/-- Where a validator is complete, whatever the spec accepts, the validator accepts. -/
theorem accepts_of_complete {v : Program} {d : VestingDatum} {r : VestingRedeemer}
    {ctx : ScriptContext} (hc : Complete v d r ctx) (h : specAccepts d r ctx = true) :
    validatorAccepts ctx v :=
  hc h

/-! ## Shapes used below -/

/-- A datum with a key beneficiary and a single vested asset. -/
def keyDatum (bh : PubKeyHash) (locker : Credential) (a : VestedAsset)
    (start finish recovery : Integer) : VestingDatum :=
  ⟨.PubKeyCredential bh, locker, [a], start, finish, recovery⟩

/-- A claim with validity range `[now, +∞)`, the vesting UTxO as the only input, and
only continuation outputs. -/
def claimAt (d : VestingDatum) (ownRef : TxOutRef) (sh : ScriptHash)
    (ownValue : List (Data × Data)) (now : Integer) (sigs : List PubKeyHash)
    (wdrl : List (Credential × Integer)) (outs : List ScriptOut) (rest : TxInfo) : ClaimTx :=
  ⟨d, ownRef, sh, ownValue, none, none,
    ⟨.FiniteLowerBound now true, .InfiniteUpperBound .PosInf⟩, sigs, wdrl, outs, none, rest⟩

/-- A claim with validity range `[now, +∞)` and one output, at any address. -/
def claimAnyOutAt (d : VestingDatum) (ownRef : TxOutRef) (sh : ScriptHash)
    (ownValue : List (Data × Data)) (now : Integer) (sigs : List PubKeyHash)
    (wdrl : List (Credential × Integer)) (out : AnyOut) (rest : TxInfo) : ClaimAnyOutTx :=
  ⟨d, ownRef, sh, ownValue, ⟨.FiniteLowerBound now true, .InfiniteUpperBound .PosInf⟩,
    sigs, wdrl, out, rest⟩

/-- A cancel with a validity range starting, inclusively, at `now`, and any upper
bound. -/
def cancelAt (d : VestingDatum) (ownRef : TxOutRef) (sh : ScriptHash)
    (ownValue : List (Data × Data)) (now : Integer) (up : UpperBound)
    (sigs : List PubKeyHash) (wdrl : List (Credential × Integer)) (rest : TxInfo) : CancelTx :=
  ⟨d, ownRef, sh, ownValue, ⟨.FiniteLowerBound now true, up⟩, sigs, wdrl, rest⟩

/-! ## Claims -/

/-- I2, I3: before the end of vesting, if the validator accepts a claim signed by the
beneficiary whose one output, at any script address, carries the vested asset, that
output reproduces the datum and keeps at least the required remainder. -/
theorem claim_sound_partial
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh outSh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (outDatum : Data) (wdrl : List (Credential × Integer))
    (rest : TxInfo)
    (hpol : a.policy ≠ "") (hsf : start < finish) (hnow : now < finish) :
    validatorAccepts
        (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
          [⟨outSh, outDatum, ada, a.policy, a.name, outQty⟩] rest).ctx
        spendValidator →
      outDatum = datumData (keyDatum bh locker a start finish recovery) ∧
      outQty ≥ required a.total start finish now := by
  intro hacc
  have hs := claim_sound
    (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
      [⟨outSh, outDatum, ada, a.policy, a.name, outQty⟩] rest)
    bh a rfl rfl rfl rfl rfl (by simp [claimAt]) (by simp [claimAt]) hacc
  clear hacc
  revert hs
  blaster

/-- I2, I3: before the end of vesting, if the validator accepts a claim signed by the
beneficiary whose one output, at any address, carries the vested asset, that output
is at the input's full address, reproduces the datum and keeps at least the required
remainder. -/
theorem claim_sound_partial_any_out
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (outAddr : Address) (outDatum : Data)
    (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hpol : a.policy ≠ "") (hsf : start < finish) (hnow : now < finish) :
    validatorAccepts
        (claimAnyOutAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh]
          wdrl ⟨outAddr, outDatum, ada, a.policy, a.name, outQty⟩ rest).ctx
        spendValidator →
      outAddr = ⟨.ScriptCredential sh, none⟩ ∧
      outDatum = datumData (keyDatum bh locker a start finish recovery) ∧
      outQty ≥ required a.total start finish now := by
  rcases outAddr with ⟨outCred, outStake⟩
  intro hacc
  have hs := claim_sound_any_out
    (claimAnyOutAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh]
      wdrl ⟨⟨outCred, outStake⟩, outDatum, ada, a.policy, a.name, outQty⟩ rest)
    bh a rfl rfl (by simp [claimAnyOutAt]) hacc
  clear hacc
  revert hs
  blaster

/-- Before vesting ends, the validator accepts this signed claim with a
nonnegative total and an output that keeps the full address, datum and remainder. -/
theorem claim_complete_partial
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hpol : a.policy ≠ "") (hTotal : 0 ≤ a.total) (hsf : start < finish) (hnow : now < finish)
    (hq : outQty ≥ required a.total start finish now) :
    validatorAccepts
      (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
        [⟨sh, datumData (keyDatum bh locker a start finish recovery), ada, a.policy, a.name,
          outQty⟩] rest).ctx
      spendValidator := by
  apply claim_complete
    (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
      [⟨sh, datumData (keyDatum bh locker a start finish recovery), ada, a.policy, a.name,
        outQty⟩] rest)
    bh a rfl rfl rfl rfl rfl (by simp [claimAt]) (by simp [claimAt])
  blaster

/-- Before vesting ends, the validator accepts this signed claim with a
nonnegative total and an output that keeps the full address, datum and remainder. -/
theorem claim_complete_partial_any_out
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (outAddr : Address)
    (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hpol : a.policy ≠ "") (hTotal : 0 ≤ a.total) (hsf : start < finish) (hnow : now < finish)
    (hAddr : outAddr = ⟨.ScriptCredential sh, none⟩)
    (hq : outQty ≥ required a.total start finish now) :
    validatorAccepts
      (claimAnyOutAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh]
        wdrl ⟨outAddr, datumData (keyDatum bh locker a start finish recovery), ada, a.policy,
          a.name, outQty⟩ rest).ctx
      spendValidator := by
  subst outAddr
  apply claim_complete_any_out
    (claimAnyOutAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh]
      wdrl ⟨⟨.ScriptCredential sh, none⟩, datumData (keyDatum bh locker a start finish recovery),
        ada, a.policy, a.name, outQty⟩ rest)
    bh a rfl rfl (by simp [claimAnyOutAt])
  blaster

/-- At or after vesting ends, the validator accepts this signed claim with a
nonnegative total, whatever its output at a script address holds. -/
theorem claim_complete_full
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now : Integer) (out : ScriptOut) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hTotal : 0 ≤ a.total) (hsf : start < finish) (hafter : finish ≤ now) :
    validatorAccepts
      (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
        [out] rest).ctx
      spendValidator := by
  apply claim_complete
    (claimAt (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
      [out] rest)
    bh a rfl rfl rfl rfl rfl (by simp [claimAt]) (by simp [claimAt])
  blaster

/-! ## Cancels -/

/-- R6, C7: if the validator accepts a cancel signed by a key locker, with a validity
range starting, inclusively, at `now`, then `now` is after the recovery time. -/
theorem cancel_sound_after_recovery
    (bene : Credential) (lk : PubKeyHash) (vesting : List VestedAsset)
    (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (now : Integer)
    (up : UpperBound) (wdrl : List (Credential × Integer)) (rest : TxInfo) :
    validatorAccepts
        (cancelAt ⟨bene, .PubKeyCredential lk, vesting, start, finish, recovery⟩ ownRef sh
          ownValue now up [lk] wdrl rest).ctx
        spendValidator →
      recovery < now := by
  intro hacc
  have hs := cancel_sound
    (cancelAt ⟨bene, .PubKeyCredential lk, vesting, start, finish, recovery⟩ ownRef sh
      ownValue now up [lk] wdrl rest)
    (by intro _ _; simp [cancelAt]) (by intro _ h; cases h) hacc
  clear hacc
  revert hs
  blaster

/-- §8.3, C6–C8: the validator accepts a cancel signed by a key locker, on a schedule
ordered `start < end < recovery`, with a validity range starting, inclusively, after
the recovery time. -/
theorem cancel_complete_after_recovery
    (bene : Credential) (lk : PubKeyHash) (vesting : List VestedAsset)
    (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (now : Integer)
    (up : UpperBound) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hsf : start < finish) (hfr : finish < recovery) (hnow : recovery < now) :
    validatorAccepts
      (cancelAt ⟨bene, .PubKeyCredential lk, vesting, start, finish, recovery⟩ ownRef sh
        ownValue now up [lk] wdrl rest).ctx
      spendValidator := by
  apply cancel_complete
    (cancelAt ⟨bene, .PubKeyCredential lk, vesting, start, finish, recovery⟩ ownRef sh
      ownValue now up [lk] wdrl rest)
    (by intro _ _; simp [cancelAt]) (by intro _ h; cases h)
  blaster

end Formal.LinearVesting.Corollaries

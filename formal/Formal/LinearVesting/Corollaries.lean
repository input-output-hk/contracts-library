import Blaster
import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.SpecNew
import Formal.LinearVesting.Script
import Formal.LinearVesting.Cancel
import Formal.LinearVesting.Claim

/-!
# Corollaries of `cancel_agrees` and `claim_agrees`

The theorems of `Soundness.lean` and `Completeness.lean` that fall within the
coverage of the agreement theorems, restated against `SpecNew`.

Each proof uses the agreement theorem to replace the validator by `specAccepts`,
then proves the property of the spec alone. That step runs no UPLC, so `blaster`
only has the spec's own definitions to evaluate.

Fields the old theorems fixed but the validator does not depend on (the output
reference, the script hash, the spent UTxO's value, the withdrawals, the rest of
the transaction info, the upper bound for cancel) are left arbitrary here.
-/

namespace Formal.LinearVesting.Corollaries

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.V1.Time (UpperBound)
open CardanoLedgerApi.V1.Value (CurrencySymbol TokenName)
open CardanoLedgerApi.V3 (Credential PubKeyHash ScriptHash TxInfo TxOutRef)
open Formal.Shared.Common (validatorAccepts)
open Formal.LinearVesting.SpecNew (VestedAsset VestingDatum datumData required)
open Formal.LinearVesting.Script (spendValidator)
open Formal.LinearVesting.Cancel (CancelTx cancel_agrees agreesOn Agrees)
open Formal.LinearVesting.Claim (ClaimOut ClaimTx claim_agrees claimAgreesOn)

/-! ## Shapes -/

/-- A datum with a key beneficiary and a single vested asset. -/
def keyDatum (bh : PubKeyHash) (locker : Credential) (a : VestedAsset)
    (start finish recovery : Integer) : VestingDatum :=
  ⟨.PubKeyCredential bh, locker, [a], start, finish, recovery⟩

/-- The datum the old theorems call `dConcrete`: 100 of `policyA.assetA`, vesting
from 1000 to 2000, recoverable after 3000. -/
def dConcrete : VestingDatum :=
  keyDatum "beneficiary_key_hash" (.PubKeyCredential "locker_key_hash")
    ⟨"policyA", "assetA", 100⟩ 1000 2000 3000

/-- A claim spending the vesting UTxO alone, with validity range `[now, +∞)`. -/
def claimTx (d : VestingDatum) (ownRef : TxOutRef) (sh : ScriptHash)
    (ownValue : List (Data × Data)) (now : Integer) (sigs : List PubKeyHash)
    (wdrl : List (Credential × Integer)) (outs : List ClaimOut) (rest : TxInfo) : ClaimTx :=
  { datum := d, ownRef := ownRef, scriptHash := sh, ownValue := ownValue,
    range := ⟨.FiniteLowerBound now true, .InfiniteUpperBound .PosInf⟩,
    signatories := sigs, withdrawals := wdrl, outputs := outs, rest := rest }

/-- A cancel of the vesting UTxO, with validity range starting at `now` (inclusive)
and any upper bound. -/
def cancelTx (d : VestingDatum) (ownRef : TxOutRef) (sh : ScriptHash)
    (ownValue : List (Data × Data)) (now : Integer) (up : UpperBound)
    (sigs : List PubKeyHash) (wdrl : List (Credential × Integer)) (rest : TxInfo) : CancelTx :=
  { datum := d, ownRef := ownRef, scriptHash := sh, ownValue := ownValue,
    range := ⟨.FiniteLowerBound now true, up⟩,
    signatories := sigs, withdrawals := wdrl, rest := rest }

/-! ## Claim: soundness -/

/-- Before vesting ends, if the validator accepts a claim whose one output carries
the vested asset, that output reproduces the datum and keeps at least the
required remainder (spec §9 I2/I3). Parallel to `Soundness.claim_sound_partial`,
for an output at any script address. -/
theorem claim_sound_partial
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh outSh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (outDatum : Data) (wdrl : List (Credential × Integer))
    (rest : TxInfo)
    (hpol : a.policy ≠ "") (hsf : start < finish) (hnow : now < finish) :
    validatorAccepts
        (claimTx (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
          [⟨outSh, outDatum, ada, a.policy, a.name, outQty⟩] rest).ctx
        spendValidator →
      outDatum = datumData (keyDatum bh locker a start finish recovery) ∧
      outQty ≥ required a.total start finish now := by
  intro hacc
  have h := claim_agrees
    (claimTx (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
      [⟨outSh, outDatum, ada, a.policy, a.name, outQty⟩] rest)
    bh a rfl rfl rfl (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  have hs := h.mp hacc
  clear h hacc
  revert hs
  blaster

/-- At `now = 1500`, an accepted claim's output reproduces the datum and keeps at
least 50 (spec §9 I2/I3). Parallel to `Soundness.claim_sound_partial_concrete`. -/
theorem claim_sound_partial_concrete
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (ada outQty : Integer) (outDatum : Data) (wdrl : List (Credential × Integer))
    (rest : TxInfo) :
    validatorAccepts
        (claimTx dConcrete ownRef sh ownValue 1500 ["beneficiary_key_hash"] wdrl
          [⟨sh, outDatum, ada, "policyA", "assetA", outQty⟩] rest).ctx
        spendValidator →
      outDatum = datumData dConcrete ∧ outQty ≥ 50 := by
  intro hacc
  have h := claim_agrees
    (claimTx dConcrete ownRef sh ownValue 1500 ["beneficiary_key_hash"] wdrl
      [⟨sh, outDatum, ada, "policyA", "assetA", outQty⟩] rest)
    "beneficiary_key_hash" ⟨"policyA", "assetA", 100⟩ rfl rfl rfl
    (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  have hs := h.mp hacc
  clear h hacc
  revert hs
  blaster

/-! ## Claim: completeness -/

/-- Before vesting ends, a claim signed by the beneficiary, whose one output is at
the script, reproduces the datum and keeps the required remainder, is accepted
(spec §8 C1–C4). Parallel to `Completeness.claim_complete_partial`, for an output
with no staking credential. -/
theorem claim_complete_partial
    (bh : PubKeyHash) (locker : Credential) (a : VestedAsset) (start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hpol : a.policy ≠ "") (hsf : start < finish) (hnow : now < finish)
    (hq : outQty ≥ required a.total start finish now) :
    validatorAccepts
      (claimTx (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
        [⟨sh, datumData (keyDatum bh locker a start finish recovery), ada, a.policy, a.name,
          outQty⟩] rest).ctx
      spendValidator := by
  have h := claim_agrees
    (claimTx (keyDatum bh locker a start finish recovery) ownRef sh ownValue now [bh] wdrl
      [⟨sh, datumData (keyDatum bh locker a start finish recovery), ada, a.policy, a.name,
        outQty⟩] rest)
    bh a rfl rfl rfl (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  rw [h]
  clear h
  blaster

/-- The concrete partial claim at `now = 1500`, keeping all 100, is accepted.
Parallel to `Completeness.claim_accept_concrete`. -/
theorem claim_accept_concrete
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (ada : Integer)
    (wdrl : List (Credential × Integer)) (rest : TxInfo) :
    validatorAccepts
      (claimTx dConcrete ownRef sh ownValue 1500 ["beneficiary_key_hash"] wdrl
        [⟨sh, datumData dConcrete, ada, "policyA", "assetA", 100⟩] rest).ctx
      spendValidator := by
  have h := claim_agrees
    (claimTx dConcrete ownRef sh ownValue 1500 ["beneficiary_key_hash"] wdrl
      [⟨sh, datumData dConcrete, ada, "policyA", "assetA", 100⟩] rest)
    "beneficiary_key_hash" ⟨"policyA", "assetA", 100⟩ rfl rfl rfl
    (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  rw [h]
  clear h
  blaster

/-- A claim keeping the whole bundle is accepted at any `now`, with any ada
amounts. Parallel to `Completeness.claim_accept_anytime`. -/
theorem claim_accept_anytime
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (now ada : Integer)
    (wdrl : List (Credential × Integer)) (rest : TxInfo) :
    validatorAccepts
      (claimTx dConcrete ownRef sh ownValue now ["beneficiary_key_hash"] wdrl
        [⟨sh, datumData dConcrete, ada, "policyA", "assetA", 100⟩] rest).ctx
      spendValidator := by
  have h := claim_agrees
    (claimTx dConcrete ownRef sh ownValue now ["beneficiary_key_hash"] wdrl
      [⟨sh, datumData dConcrete, ada, "policyA", "assetA", 100⟩] rest)
    "beneficiary_key_hash" ⟨"policyA", "assetA", 100⟩ rfl rfl rfl
    (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  rw [h]
  clear h
  blaster

/-- With every schedule value symbolic and `start < now < finish`, a claim keeping
at least the required remainder is accepted. Parallel to
`Completeness.claim_accept_generic_schedule`. -/
theorem claim_accept_generic_schedule
    (bene : PubKeyHash) (locker : Credential) (policy : CurrencySymbol) (name : TokenName) (total start finish recovery : Integer)
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hpol : policy ≠ "") (htot : 0 ≤ total) (hlo : start < now) (hhi : now < finish)
    (hq : outQty ≥ required total start finish now) :
    validatorAccepts
      (claimTx (keyDatum bene locker ⟨policy, name, total⟩ start finish recovery) ownRef sh
        ownValue now [bene] wdrl
        [⟨sh, datumData (keyDatum bene locker ⟨policy, name, total⟩ start finish recovery), ada,
          policy, name, outQty⟩] rest).ctx
      spendValidator := by
  have h := claim_agrees
    (claimTx (keyDatum bene locker ⟨policy, name, total⟩ start finish recovery) ownRef sh
      ownValue now [bene] wdrl
      [⟨sh, datumData (keyDatum bene locker ⟨policy, name, total⟩ start finish recovery), ada,
        policy, name, outQty⟩] rest)
    bene ⟨policy, name, total⟩ rfl rfl rfl (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  rw [h]
  clear h
  blaster

/-- At or after the end of vesting, a claim is accepted whatever its one output
keeps (spec §8.2 I4). Parallel to `Completeness.claim_complete_full`. -/
theorem claim_complete_full
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data))
    (now ada outQty : Integer) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hge : 2000 ≤ now) (hq : 0 ≤ outQty) :
    validatorAccepts
      (claimTx dConcrete ownRef sh ownValue now ["beneficiary_key_hash"] wdrl
        [⟨sh, datumData dConcrete, ada, "policyA", "assetA", outQty⟩] rest).ctx
      spendValidator := by
  have h := claim_agrees
    (claimTx dConcrete ownRef sh ownValue now ["beneficiary_key_hash"] wdrl
      [⟨sh, datumData dConcrete, ada, "policyA", "assetA", outQty⟩] rest)
    "beneficiary_key_hash" ⟨"policyA", "assetA", 100⟩ rfl rfl rfl
    (by simp [claimTx]) (by simp [claimTx])
  unfold claimAgreesOn Agrees at h
  rw [h]
  clear h
  blaster

/-! ## Cancel -/

/-- If the validator accepts a cancel signed by the locker, `now` is after the
recovery time (spec §9 R6, C7). Parallel to `Soundness.cancel_sound`. -/
theorem cancel_sound
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (now : Integer)
    (up : UpperBound) (wdrl : List (Credential × Integer)) (rest : TxInfo) :
    validatorAccepts
        (cancelTx dConcrete ownRef sh ownValue now up ["locker_key_hash"] wdrl rest).ctx
        spendValidator →
      3000 < now := by
  intro hacc
  have h := cancel_agrees
    (cancelTx dConcrete ownRef sh ownValue now up ["locker_key_hash"] wdrl rest)
    (by intro _ _; simp [cancelTx]) (by intro _ h; cases h)
  unfold agreesOn Agrees at h
  have hs := h.mp hacc
  clear h hacc
  revert hs
  blaster

/-- The locker can cancel at any `now` after the recovery time (spec §8.3).
Parallel to `Completeness.cancel_complete`. -/
theorem cancel_complete
    (ownRef : TxOutRef) (sh : ScriptHash) (ownValue : List (Data × Data)) (now : Integer)
    (up : UpperBound) (wdrl : List (Credential × Integer)) (rest : TxInfo)
    (hgt : 3000 < now) :
    validatorAccepts
      (cancelTx dConcrete ownRef sh ownValue now up ["locker_key_hash"] wdrl rest).ctx
      spendValidator := by
  have h := cancel_agrees
    (cancelTx dConcrete ownRef sh ownValue now up ["locker_key_hash"] wdrl rest)
    (by intro _ _; simp [cancelTx]) (by intro _ h; cases h)
  unfold agreesOn Agrees at h
  rw [h]
  clear h
  blaster

end Formal.LinearVesting.Corollaries
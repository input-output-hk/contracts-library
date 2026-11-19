import Blaster
import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.TxBuilder

/-!
# Tests on fixed transactions

Each case is one concrete transaction, run through both the spec (`spec_…`) and the
compiled validator (`validator_…`), with the expected outcome stated.
They do not use the agreement theorems, so they are an independent check that the
two give the same answer, and they cover boundaries (exact remainder, rounding,
inclusive and exclusive bounds).

A few cases keep one value symbolic (a signer, a hash, a time), as the earlier
`Soundness`, `Completeness` and `Robustness` files did.

The last section has malformed inputs, which the spec cannot express because it
takes a typed datum and redeemer: those are run through the validator only.

Fixtures: a key beneficiary, a key locker, one vested asset of 1000 units, and the
schedule start 1000, end 2000, recovery 3000.
-/

namespace Formal.LinearVesting.Tests

open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.V1.Value (CurrencySymbol TokenName)
open CardanoLedgerApi.V3
  (Credential POSIXTimeRange PubKeyHash ScriptContext ScriptHash TxInfo TxOutRef)
open Formal.Shared.Common (validatorAccepts validatorRejects)
open Formal.LinearVesting.Spec
  (VestedAsset VestingDatum VestingRedeemer datumData redeemerData specAccepts)
open Formal.LinearVesting.Script (spendValidator)
open Formal.LinearVesting.TxBuilder

/-! ## Fixtures -/

def sh : ScriptHash := "5c"
def otherSh : ScriptHash := "5d"
def ben : PubKeyHash := "be"
def lk : PubKeyHash := "10"
def pol : CurrencySymbol := "70"
def tok : TokenName := "7e"
def ref0 : TxOutRef := ⟨"aa", 0⟩
def ref1 : TxOutRef := ⟨"aa", 1⟩

/-- A transaction info with every field empty; the shapes replace what is read. -/
def emptyInfo : TxInfo :=
  ⟨[], [], [], 0, [], [], [], Data.I 0, [], [], [], "", [], [], Data.Constr 1 [],
    Data.Constr 1 []⟩

/-- A value of `ada` lovelace and `qty` units of the vested asset. -/
def val (ada qty : Integer) : List (Data × Data) :=
  [(Data.B "", Data.Map [(Data.B "", Data.I ada)]),
   (Data.B pol, Data.Map [(Data.B tok, Data.I qty)])]

def adaOnly (ada : Integer) : List (Data × Data) :=
  [(Data.B "", Data.Map [(Data.B "", Data.I ada)])]

def dKey : VestingDatum :=
  ⟨.PubKeyCredential ben, .PubKeyCredential lk, [⟨pol, tok, 1000⟩], 1000, 2000, 3000⟩

/-- 7 units, so that the vested amount is not a whole number half-way. -/
def dOdd : VestingDatum :=
  ⟨.PubKeyCredential ben, .PubKeyCredential lk, [⟨pol, tok, 7⟩], 1000, 2000, 3000⟩

/-- A script beneficiary `b`. -/
def dScript (b : ScriptHash) : VestingDatum :=
  ⟨.ScriptCredential b, .PubKeyCredential lk, [⟨pol, tok, 1000⟩], 1000, 2000, 3000⟩

/-- Start equal to end. -/
def dBadSchedule : VestingDatum :=
  ⟨.PubKeyCredential ben, .PubKeyCredential lk, [⟨pol, tok, 1000⟩], 2000, 2000, 3000⟩

/-- End equal to recovery. -/
def dBadRecovery : VestingDatum :=
  ⟨.PubKeyCredential ben, .PubKeyCredential lk, [⟨pol, tok, 1000⟩], 1000, 2000, 2000⟩

/-- `[t, +∞)`. -/
def fromT (t : Integer) : POSIXTimeRange :=
  ⟨.FiniteLowerBound t true, .InfiniteUpperBound .PosInf⟩

/-- A continuation of `d` at the vesting script holding `qty` units. -/
def cont (d : VestingDatum) (qty : Integer) : ScriptOut :=
  ⟨sh, datumData d, 2000000, pol, tok, qty⟩

/-- A claim of the vesting UTxO alone, with the given range, signatories,
withdrawals and continuations. -/
def claim (d : VestingDatum) (range : POSIXTimeRange) (sigs : List PubKeyHash)
    (wdrl : List (Credential × Integer)) (conts : List ScriptOut) : ScriptContext :=
  (⟨d, ref0, sh, val 2000000 1000, none, none, range, sigs, wdrl, conts, none, emptyInfo⟩
    : ClaimTx).ctx

/-- A cancel with the given range and signatories. -/
def cancel (d : VestingDatum) (range : POSIXTimeRange) (sigs : List PubKeyHash) :
    ScriptContext :=
  (⟨d, ref0, sh, val 2000000 1000, range, sigs, [], emptyInfo⟩ : CancelTx).ctx

/-! ## Claim: amounts and time -/

/-- Half-way, 500 vested: a continuation keeping exactly 500 is enough. -/
def claimHalfway := claim dKey (fromT 1500) [ben] [] [cont dKey 500]
theorem spec_accept_claim_halfway : specAccepts dKey .claim claimHalfway = true := by
  blaster
theorem validator_accept_claim_halfway : validatorAccepts claimHalfway spendValidator := by
  blaster

/-- Half-way, keeping 499 releases one unit too many. -/
def claimOverRelease := claim dKey (fromT 1500) [ben] [] [cont dKey 499]
theorem spec_reject_claim_over_release :
    specAccepts dKey .claim claimOverRelease = false := by
  blaster
theorem validator_reject_claim_over_release :
    validatorRejects claimOverRelease spendValidator := by
  blaster

/-- At the start nothing is vested: keeping all 1000 is accepted. -/
def claimAtStart := claim dKey (fromT 1000) [ben] [] [cont dKey 1000]
theorem spec_accept_claim_at_start : specAccepts dKey .claim claimAtStart = true := by
  blaster
theorem validator_accept_claim_at_start : validatorAccepts claimAtStart spendValidator := by
  blaster

/-- At the start, keeping 999 is rejected. -/
def claimAtStartPartial := claim dKey (fromT 1000) [ben] [] [cont dKey 999]
theorem spec_reject_claim_at_start :
    specAccepts dKey .claim claimAtStartPartial = false := by
  blaster
theorem validator_reject_claim_at_start :
    validatorRejects claimAtStartPartial spendValidator := by
  blaster

/-- Keeping the whole 1000 is accepted at any time, whatever the ada amounts. -/
def claimAnytime (now inAda outAda : Integer) :=
  (⟨dKey, ref0, sh, val inAda 1000, none, none, fromT now, [ben], [],
    [⟨sh, datumData dKey, outAda, pol, tok, 1000⟩], none, emptyInfo⟩ : ClaimTx).ctx
theorem spec_accept_claim_anytime (now inAda outAda : Integer) :
    specAccepts dKey .claim (claimAnytime now inAda outAda) = true := by
  blaster
theorem validator_accept_claim_anytime (now inAda outAda : Integer) :
    validatorAccepts (claimAnytime now inAda outAda) spendValidator := by
  blaster

/-- 7 units half-way: 3 vested (3.5 rounded down), so 4 must stay. -/
def claimRounding := claim dOdd (fromT 1500) [ben] [] [cont dOdd 4]
theorem spec_accept_claim_rounding : specAccepts dOdd .claim claimRounding = true := by
  blaster
theorem validator_accept_claim_rounding :
    validatorAccepts claimRounding spendValidator := by
  blaster

/-- 7 units half-way: keeping 3 is rejected. -/
def claimRoundingOver := claim dOdd (fromT 1500) [ben] [] [cont dOdd 3]
theorem spec_reject_claim_rounding :
    specAccepts dOdd .claim claimRoundingOver = false := by
  blaster
theorem validator_reject_claim_rounding :
    validatorRejects claimRoundingOver spendValidator := by
  blaster

/-- At the end everything is vested: a claim with no outputs is accepted. -/
def claimAtEnd := claim dKey (fromT 2000) [ben] [] []
theorem spec_accept_claim_at_end : specAccepts dKey .claim claimAtEnd = true := by
  blaster
theorem validator_accept_claim_at_end : validatorAccepts claimAtEnd spendValidator := by
  blaster

/-- One unit before the end, a claim with no outputs is rejected. -/
def claimBeforeEnd := claim dKey (fromT 1999) [ben] [] []
theorem spec_reject_claim_before_end : specAccepts dKey .claim claimBeforeEnd = false := by
  blaster
theorem validator_reject_claim_before_end :
    validatorRejects claimBeforeEnd spendValidator := by
  blaster

/-- A range with no lower bound gives no time to vest against. -/
def claimNoTime :=
  claim dKey ⟨.InfiniteLowerBound .NegInf, .InfiniteUpperBound .PosInf⟩ [ben] []
    [cont dKey 1000]
theorem spec_reject_claim_no_time : specAccepts dKey .claim claimNoTime = false := by
  blaster
theorem validator_reject_claim_no_time : validatorRejects claimNoTime spendValidator := by
  blaster

/-! ## Claim: authorization -/

/-- Signed by any key other than the beneficiary's. -/
def claimWrongSigner (w : PubKeyHash) := claim dKey (fromT 1500) [w] [] [cont dKey 500]
theorem spec_reject_claim_wrong_signer (w : PubKeyHash) (hw : w ≠ ben) :
    specAccepts dKey .claim (claimWrongSigner w) = false := by
  blaster
theorem validator_reject_claim_wrong_signer (w : PubKeyHash) (hw : w ≠ ben) :
    validatorRejects (claimWrongSigner w) spendValidator := by
  blaster

/-- Not signed at all. -/
def claimNoSignatories := claim dKey (fromT 1500) [] [] [cont dKey 500]
theorem spec_reject_claim_no_signatories :
    specAccepts dKey .claim claimNoSignatories = false := by
  blaster
theorem validator_reject_claim_no_signatories :
    validatorRejects claimNoSignatories spendValidator := by
  blaster

/-- Any script beneficiary `b` authorizes by a withdrawal from its credential. -/
def claimScript (b : ScriptHash) :=
  claim (dScript b) (fromT 1500) [] [(.ScriptCredential b, 0)] [cont (dScript b) 500]
theorem spec_accept_claim_script (b : ScriptHash) :
    specAccepts (dScript b) .claim (claimScript b) = true := by
  blaster
theorem validator_accept_claim_script (b : ScriptHash) :
    validatorAccepts (claimScript b) spendValidator := by
  blaster

/-- Any script beneficiary `b`, without the withdrawal. -/
def claimScriptNoWithdrawal (b : ScriptHash) :=
  claim (dScript b) (fromT 1500) [] [] [cont (dScript b) 500]
theorem spec_reject_claim_no_withdrawal (b : ScriptHash) :
    specAccepts (dScript b) .claim (claimScriptNoWithdrawal b) = false := by
  blaster
theorem validator_reject_claim_no_withdrawal (b : ScriptHash) :
    validatorRejects (claimScriptNoWithdrawal b) spendValidator := by
  blaster

/-! ## Claim: continuations -/

/-- The continuation changes the recovery time. -/
def claimDatumTamper :=
  claim dKey (fromT 1500) [ben] []
    [⟨sh, datumData { dKey with recoveryTime := 9999 }, 2000000, pol, tok, 500⟩]
theorem spec_reject_claim_datum_tamper :
    specAccepts dKey .claim claimDatumTamper = false := by
  blaster
theorem validator_reject_claim_datum_tamper :
    validatorRejects claimDatumTamper spendValidator := by
  blaster

/-- The continuation is at another script. -/
def claimOtherScript :=
  claim dKey (fromT 1500) [ben] [] [⟨otherSh, datumData dKey, 2000000, pol, tok, 500⟩]
theorem spec_reject_claim_other_script :
    specAccepts dKey .claim claimOtherScript = false := by
  blaster
theorem validator_reject_claim_other_script :
    validatorRejects claimOtherScript spendValidator := by
  blaster

/-- The vesting UTxO holds its datum by any hash `h` instead of inline. -/
def claimDatumHash (h : ByteString) :=
  spendCtx emptyInfo
    [⟨ref0, ⟨⟨.ScriptCredential sh, none⟩, val 2000000 1000, .OutputDatumHash h, none⟩⟩]
    [(cont dKey 500).toTxOut] [] (fromT 1500) [ben] .claim ref0 dKey
theorem spec_reject_claim_datum_hash (h : ByteString) :
    specAccepts dKey .claim (claimDatumHash h) = false := by
  blaster
theorem validator_reject_claim_datum_hash (h : ByteString) :
    validatorRejects (claimDatumHash h) spendValidator := by
  blaster

/-- The typical claim: a wallet input for the fee, a payout to the beneficiary, and a
finite upper bound. -/
def claimTypical :=
  (⟨dKey, ref0, sh, val 2000000 1000, none, some ⟨⟨"cc", 0⟩, ben, adaOnly 5000000⟩,
    ⟨.FiniteLowerBound 1500 true, .FiniteUpperBound 1600 true⟩, [ben], [], [cont dKey 500],
    some ⟨ben, val 4000000 500⟩, emptyInfo⟩ : ClaimTx).ctx
theorem spec_accept_claim_typical : specAccepts dKey .claim claimTypical = true := by
  blaster
theorem validator_accept_claim_typical : validatorAccepts claimTypical spendValidator := by
  blaster

/-- Two vesting UTxOs with the same datum, each with its own continuation. -/
def claimBatch :=
  (⟨dKey, ref0, sh, val 2000000 1000, some (ref1, val 2000000 1000), none, fromT 1500,
    [ben], [], [cont dKey 500, cont dKey 500], none, emptyInfo⟩ : ClaimTx).ctx
theorem spec_accept_claim_batch : specAccepts dKey .claim claimBatch = true := by
  blaster
theorem validator_accept_claim_batch : validatorAccepts claimBatch spendValidator := by
  blaster

/-- Two vesting UTxOs with the same datum, but one continuation for both. -/
def claimDoubleSatisfaction :=
  (⟨dKey, ref0, sh, val 2000000 1000, some (ref1, val 2000000 1000), none, fromT 1500,
    [ben], [], [cont dKey 500], none, emptyInfo⟩ : ClaimTx).ctx
theorem spec_reject_claim_double_satisfaction :
    specAccepts dKey .claim claimDoubleSatisfaction = false := by
  blaster
theorem validator_reject_claim_double_satisfaction :
    validatorRejects claimDoubleSatisfaction spendValidator := by
  blaster

/-- Two vesting UTxOs with the same datum, and one continuation holding what both
need together. -/
def claimMergedInstances :=
  (⟨dKey, ref0, sh, val 2000000 1000, some (ref1, val 2000000 1000), none, fromT 1500,
    [ben], [], [cont dKey 1000], none, emptyInfo⟩ : ClaimTx).ctx
theorem spec_reject_claim_merged_instances :
    specAccepts dKey .claim claimMergedInstances = false := by
  blaster
theorem validator_reject_claim_merged_instances :
    validatorRejects claimMergedInstances spendValidator := by
  blaster

/-- Two vesting UTxOs with the same datum, and two continuations holding enough
together (1000) but one of them less than its own 500. -/
def claimUnderfundedBatch :=
  (⟨dKey, ref0, sh, val 2000000 1000, some (ref1, val 2000000 1000), none, fromT 1500,
    [ben], [], [cont dKey 400, cont dKey 600], none, emptyInfo⟩ : ClaimTx).ctx
theorem spec_reject_claim_underfunded_batch :
    specAccepts dKey .claim claimUnderfundedBatch = false := by
  blaster
theorem validator_reject_claim_underfunded_batch :
    validatorRejects claimUnderfundedBatch spendValidator := by
  blaster

/-- Start equal to end. -/
def claimBadSchedule := claim dBadSchedule (fromT 2500) [ben] [] []
theorem spec_reject_claim_bad_schedule :
    specAccepts dBadSchedule .claim claimBadSchedule = false := by
  blaster
theorem validator_reject_claim_bad_schedule :
    validatorRejects claimBadSchedule spendValidator := by
  blaster

/-! ## Cancel -/

/-- After recovery, signed by the locker. -/
def cancelAfter := cancel dKey (fromT 3001) [lk]
theorem spec_accept_cancel : specAccepts dKey .cancel cancelAfter = true := by
  blaster
theorem validator_accept_cancel : validatorAccepts cancelAfter spendValidator := by
  blaster

/-- A range starting inclusively at the recovery time is too early. -/
def cancelAtRecovery := cancel dKey (fromT 3000) [lk]
theorem spec_reject_cancel_at_recovery :
    specAccepts dKey .cancel cancelAtRecovery = false := by
  blaster
theorem validator_reject_cancel_at_recovery :
    validatorRejects cancelAtRecovery spendValidator := by
  blaster

/-- A range starting exclusively at the recovery time is entirely after it. -/
def cancelAfterRecoveryExclusive :=
  cancel dKey ⟨.FiniteLowerBound 3000 false, .InfiniteUpperBound .PosInf⟩ [lk]
theorem spec_accept_cancel_exclusive :
    specAccepts dKey .cancel cancelAfterRecoveryExclusive = true := by
  blaster
theorem validator_accept_cancel_exclusive :
    validatorAccepts cancelAfterRecoveryExclusive spendValidator := by
  blaster

/-- Before recovery. -/
def cancelPremature := cancel dKey (fromT 2500) [lk]
theorem spec_reject_cancel_premature : specAccepts dKey .cancel cancelPremature = false := by
  blaster
theorem validator_reject_cancel_premature :
    validatorRejects cancelPremature spendValidator := by
  blaster

/-- Signed by the beneficiary instead of the locker. -/
def cancelWrongSigner := cancel dKey (fromT 3001) [ben]
theorem spec_reject_cancel_wrong_signer :
    specAccepts dKey .cancel cancelWrongSigner = false := by
  blaster
theorem validator_reject_cancel_wrong_signer :
    validatorRejects cancelWrongSigner spendValidator := by
  blaster

/-- After recovery, but not signed at all. -/
def cancelUnsigned := cancel dKey (fromT 3001) []
theorem spec_reject_cancel_unsigned : specAccepts dKey .cancel cancelUnsigned = false := by
  blaster
theorem validator_reject_cancel_unsigned :
    validatorRejects cancelUnsigned spendValidator := by
  blaster

/-- End equal to recovery. -/
def cancelBadSchedule := cancel dBadRecovery (fromT 3001) [lk]
theorem spec_reject_cancel_bad_schedule :
    specAccepts dBadRecovery .cancel cancelBadSchedule = false := by
  blaster
theorem validator_reject_cancel_bad_schedule :
    validatorRejects cancelBadSchedule spendValidator := by
  blaster

/-! ## Malformed inputs (validator only) -/

/-- `claimHalfway`, which is accepted, with a redeemer that is not a constructor. -/
def malformedRedeemer : ScriptContext := { claimHalfway with scriptContextRedeemer := Data.I 0 }
theorem validator_reject_malformed_redeemer :
    validatorRejects malformedRedeemer spendValidator := by
  blaster

/-- `claimHalfway` with no datum passed to the script. -/
def missingDatum : ScriptContext :=
  { claimHalfway with scriptContextScriptInfo := .SpendingScript ref0 none }
theorem validator_reject_missing_datum : validatorRejects missingDatum spendValidator := by
  blaster

/-- `cancelAfter`, which is accepted, with a datum that is not a vesting datum. -/
def malformedDatum : ScriptContext :=
  { cancelAfter with scriptContextScriptInfo := .SpendingScript ref0 (some (Data.I 5)) }
theorem validator_reject_malformed_datum : validatorRejects malformedDatum spendValidator := by
  blaster

/-- `claimHalfway` run as a minting script. -/
def mintingPurpose : ScriptContext :=
  { claimHalfway with scriptContextScriptInfo := .MintingScript sh }
theorem validator_reject_minting_purpose : validatorRejects mintingPurpose spendValidator := by
  blaster

/-- `claimHalfway` spending a reference that is not among the inputs. -/
def ownInputMissing : ScriptContext :=
  { claimHalfway with scriptContextScriptInfo := .SpendingScript ⟨"ab", 0⟩ (some (datumData dKey)) }
theorem spec_reject_own_input_missing : specAccepts dKey .claim ownInputMissing = false := by
  blaster
theorem validator_reject_own_input_missing :
    validatorRejects ownInputMissing spendValidator := by
  blaster

end Formal.LinearVesting.Tests

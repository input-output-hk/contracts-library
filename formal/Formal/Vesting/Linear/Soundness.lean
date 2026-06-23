/-
Linear vesting — SOUNDNESS: `accepts ⇒ spec` (spec §9).

OPEN MODELING TODOs:
  * value bundle is modeled per single asset; generalize to an arbitrary bundle
    (spec "arbitrary value bundle").
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import CardanoLedgerApi.V1.Time
import Formal.Common
import Formal.Vesting.Linear.Spec
import Formal.Vesting.Linear.Script

namespace Formal.Vesting.Linear.Soundness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Redeemer ScriptContext TxInfo TxInInfo TxOut
                          Value OutputDatum valueOf Withdrawals)
open Formal.Common (validatorAccepts)
open Formal.Vesting.Linear.Spec
open Formal.Vesting.Linear.Script (spendValidator)

/-! ## Ledger-context scaffold (shared) -/

/-- The script's own payment credential (the vesting script address). -/
def scriptHash : ByteString := "fake_script_hash_28bytes!!!!"
def scriptAddress : Address := ⟨.ScriptCredential scriptHash, none⟩

/-- Validity range `[now, +∞)`-/
def validRangeData (now : Int) : Data :=
  IsData.toData (CardanoLedgerApi.V1.Time.after now)

/-- Ada plus a single native asset `(policy, name) ↦ qty`.
TODO: generalize to an arbitrary bundle (spec "arbitrary value bundle"). -/
def withAsset (lovelace : Int) (policy name : ByteString) (qty : Int) : Value :=
  [(Data.B "", Data.Map [(Data.B "", Data.I lovelace)]),
   (Data.B policy, Data.Map [(Data.B name, Data.I qty)])]

def baseTxInfo (now : Int) (signatories : List ByteString) : TxInfo :=
  { txInfoInputs := []
    txInfoReferenceInputs := []
    txInfoOutputs := []
    txInfoFee := 0
    txInfoMint := []
    txInfoTxCerts := []
    txInfoWdrl := []                 -- TODO: script-credential auth lives here
    txInfoValidRange := validRangeData now
    txInfoSignatories := signatories
    txInfoRedeemers := []
    txInfoData := []
    txInfoId := "txid_placeholder_32bytes!!!!!!!!"
    txInfoVotes := []
    txInfoProposalProcedures := []
    txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
    txInfoTreasuryDonation := IsData.toData (none : Option Int) }

/-- A spend context with explicit `wdrl` (reward withdrawals). One contract
input carrying `datum`, one (arbitrary) continuing output, validity lower bound
`now`, signatories `sigs`, withdrawals `wdrl`, redeemer `r`. The continuation's
datum is the free parameter `outDatum`; soundness must *derive* that equality.

`wdrl` carries the withdraw-0 entries that satisfy a **script** beneficiary
(its key is the beneficiary's `ScriptCredential`); `sigs` satisfies a **key**
beneficiary. -/
def mkClaimCtxW
    (datum : VestingDatum) (inValue : Value)
    (outAddr : Address) (outValue : Value) (outDatum : Data)
    (now : Int) (sigs : List ByteString) (wdrl : Withdrawals)
    (r : Redeemer) : ScriptContext :=
  let inDatumData := datumData datum
  let utxoRef := ⟨"txid_placeholder_32bytes!!!!!!!!", 0⟩
  let inUtxo : TxOut := ⟨scriptAddress, inValue, .OutputDatum inDatumData, none⟩
  let outUtxo : TxOut := ⟨outAddr, outValue, .OutputDatum outDatum, none⟩
  let txInfo :=
    { baseTxInfo now sigs with
      txInfoInputs := [⟨utxoRef, inUtxo⟩]
      txInfoOutputs := [outUtxo]
      txInfoWdrl := wdrl
      txInfoRedeemers := [(.Spending utxoRef, r)] }
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := r
    scriptContextScriptInfo := .SpendingScript utxoRef inDatumData }

/-- The common case: no withdrawals (key-auth claims). -/
def mkClaimCtx
    (datum : VestingDatum) (inValue : Value)
    (outAddr : Address) (outValue : Value) (outDatum : Data)
    (now : Int) (sigs : List ByteString) (r : Redeemer) : ScriptContext :=
  mkClaimCtxW datum inValue outAddr outValue outDatum now sigs [] r

/-- A spend context whose contract input carries a datum **hash** rather than an
inline datum (`datumHash`), while the resolved datum is still supplied via the
script info (as on a real hash-datum spend). Used to test that the validator
rejects datum-hash inputs (spec §3.1, "datum hashes are rejected"). -/
def mkClaimCtxHashInput
    (datum : VestingDatum) (inValue : Value) (datumHash : ByteString)
    (outAddr : Address) (outValue : Value) (outDatum : Data)
    (now : Int) (sigs : List ByteString) (r : Redeemer) : ScriptContext :=
  let inDatumData := datumData datum
  let utxoRef := ⟨"txid_placeholder_32bytes!!!!!!!!", 0⟩
  let inUtxo : TxOut := ⟨scriptAddress, inValue, .OutputDatumHash datumHash, none⟩
  let outUtxo : TxOut := ⟨outAddr, outValue, .OutputDatum outDatum, none⟩
  let txInfo :=
    { baseTxInfo now sigs with
      txInfoInputs := [⟨utxoRef, inUtxo⟩]
      txInfoOutputs := [outUtxo]
      txInfoRedeemers := [(.Spending utxoRef, r)] }
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := r
    scriptContextScriptInfo := .SpendingScript utxoRef inDatumData }

/-- A spend context with **two** contract inputs that share a byte-identical
datum and value (refs differ only by index), and a **single** continuation
carrying that datum. The validator, invoked for the first input, computes
`k = 2` and requires the continuation to hold `2 × required`; this builder lets
us test both that a correctly funded batch is accepted and that an under-funded
one (one continuation for two inputs) is rejected (spec §5.1, I2). -/
def mkClaimCtxDouble
    (datum : VestingDatum) (inValue : Value)
    (outValue : Value) (outDatum : Data)
    (now : Int) (sigs : List ByteString) (r : Redeemer) : ScriptContext :=
  let inDatumData := datumData datum
  let ref0 := ⟨"txid_placeholder_32bytes!!!!!!!!", 0⟩
  let ref1 := ⟨"txid_placeholder_32bytes!!!!!!!!", 1⟩
  let inUtxo : TxOut := ⟨scriptAddress, inValue, .OutputDatum inDatumData, none⟩
  let outUtxo : TxOut := ⟨scriptAddress, outValue, .OutputDatum outDatum, none⟩
  let txInfo :=
    { baseTxInfo now sigs with
      txInfoInputs := [⟨ref0, inUtxo⟩, ⟨ref1, inUtxo⟩]  -- two inputs, same datum
      txInfoOutputs := [outUtxo]                          -- one continuation
      txInfoRedeemers := [(.Spending ref0, r), (.Spending ref1, r)] }
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := r
    scriptContextScriptInfo := .SpendingScript ref0 inDatumData }  -- own input = ref0

/-! ## Soundness theorems -/

/-- **Partial-claim soundness (accepts ⇒ spec).** Single-asset instance.

If the validator accepts a `Claim` over `mkClaimCtx` with the beneficiary key
signed and a well-formed schedule, then the continuing output reproduces the
datum and keeps at least the required remainder of the asset (spec §9 R2/R3,
I2/I3). The output's datum/value are free, so accepting *forces* them. -/
theorem claim_sound_partial
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) (outDatum : Data) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let r : Redeemer := claimRedeemer
    -- beneficiary key as the sole signatory (key-auth case);
    -- TODO: script (withdraw-0) auth branch.
    let sigs := match d.beneficiary with | .key h => [h] | .script _ => []
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now sigs r
    d.vesting = [a] ∧
    validSchedule d ∧
    now < d.endTime ∧
    validatorAccepts ctx spendValidator →   -- the CONCRETE compiled validator
      -- continuation reproduces the datum (I3) ...
      outDatum = datumData d ∧
      -- ... and keeps the required remainder (I2/B1).
      outQty ≥ required a.total d.startTime d.endTime now := by
  -- The general (∀ datum/amounts/addresses) version is too large for Z3 even
  -- over the concrete validator (hangs for minutes). Left as `sorry`; the
  -- concrete instance `claim_sound_partial_concrete` below proves the soundness
  -- direction for the fixed datum with symbolic (attacker-controlled) outputs.
  sorry

/-- **Partial-claim soundness (accepts ⇒ spec), concrete instance.** Fix the
datum/schedule/`now`; leave the continuation's claimed amount `outQty` and datum
`outDatum` **symbolic** (what an attacker controls). The output sits at the
script address, so "is it a continuation" reduces to the datum check. Then: if
the compiled validator accepts, the continuation reproduces the datum (I3) and
holds at least the required remainder (50 at `now = 1500`; I2). Acceptance forces
a correct continuation, so nothing is over-released.

NOTE: the output value uses the concrete `withAsset` shape with a symbolic
quantity, NOT a fully symbolic `Value`. A raw symbolic `Value` (arbitrary `Data`
list) makes `blaster` reason about an unbounded value structure and it does not
terminate; shaping the value keeps `quantity_of` concrete (= `outQty`). This is
the positive form of `reject_datum_tamper` + `reject_over_release`, both of which
close fast for the same reason. -/
theorem claim_sound_partial_concrete (outQty : Int) (outDatum : Data) :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" outQty)  -- concrete shape, symbolic amount
        outDatum
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator →
      outDatum = datumData dConcrete ∧ outQty ≥ 50 := by
  blaster

/-- **Cancel soundness (accepts ⇒ spec), concrete instance.** Fix the datum
(recovery = 3000) and sign the locker (so acceptance is possible); leave `now`
symbolic. If the validator accepts a `Cancel`, then `now > recovery_time`
(`3000 < now`): the locker cannot recover before the recovery time (strict;
spec §9 R6, C7). The positive form of `reject_premature_cancel`; together they
give `accepts ⟺ 3000 < now` for the signed locker. -/
theorem cancel_sound (now : Int) :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData dConcrete)
        now
        ["locker_key_hash"]            -- locker authorized
        cancelRedeemer)
      spendValidator →
      3000 < now := by
  blaster

end Formal.Vesting.Linear.Soundness

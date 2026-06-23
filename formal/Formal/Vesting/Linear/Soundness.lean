/-
Linear vesting — SOUNDNESS: `accepts ⇒ spec` (spec §9).

OPEN MODELING TODOs (block real proofs):
  * `validRangeData` — encode the validity interval `[now, +∞)` exactly as the
    ledger/validator reads it (spec §5.2). Currently `sorry`.
  * script-credential authorization via withdraw-0 (`txInfoWdrl`); only the
    key branch is modeled (`Spec.keyAuthorized`).
  * value bundle is modeled per-asset and concretely; generalize to an
    arbitrary bundle (spec "arbitrary value bundle").
  * field names of `CardanoLedgerApi.V3.TxInfo`/`TxOut` are taken from the
    reference; verify against the actual library on first build.
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Formal.Common
import Formal.Vesting.Linear.Spec

namespace Formal.Vesting.Linear.Soundness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Redeemer ScriptContext TxInfo TxInInfo TxOut
                          Value OutputDatum valueOf)
open Formal.Common (validatorAccepts)
open Formal.Vesting.Linear.Spec

set_option warn.sorry false

/-! ## Ledger-context scaffold (shared) -/

/-- The script's own payment credential (the vesting script address). -/
def scriptHash : ByteString := "fake_script_hash_28bytes!!!!"
def scriptAddress : Address := ⟨.ScriptCredential scriptHash, none⟩

-- TODO: encode the validity range `[now, +∞)` as the validator reads it
-- (spec §5.2: `now` is the finite lower bound). Placeholder until then.
def validRangeData (now : Int) : Data := sorry

/-- Ada-only value of `lovelace`. -/
def adaOnly (lovelace : Int) : Value :=
  [(Data.B "", Data.Map [(Data.B "", Data.I lovelace)])]

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

/-- A spend context: one contract input carrying `datum`, one (arbitrary)
continuing output, validity lower bound `now`, signatories `sigs`, redeemer
`r`. The continuation's datum is the free parameter `outDatum`; soundness
must *derive* that equality. -/
def mkClaimCtx
    (datum : VestingDatum) (inValue : Value)
    (outAddr : Address) (outValue : Value) (outDatum : Data)
    (now : Int) (sigs : List ByteString) (r : Redeemer) : ScriptContext :=
  let inDatumData := datumData datum
  let utxoRef := ⟨"txid_placeholder_32bytes!!!!!!!!", 0⟩
  let inUtxo : TxOut := ⟨scriptAddress, inValue, .OutputDatum inDatumData, none⟩
  let outUtxo : TxOut := ⟨outAddr, outValue, .OutputDatum outDatum, none⟩
  let txInfo :=
    { baseTxInfo now sigs with
      txInfoInputs := [⟨utxoRef, inUtxo⟩]
      txInfoOutputs := [outUtxo]
      txInfoRedeemers := [(.Spending utxoRef, r)] }
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := r
    scriptContextScriptInfo := .SpendingScript utxoRef inDatumData }

/-! ## Soundness theorems -/

/-- **Partial-claim soundness (accepts ⇒ spec).** Single-asset instance.

If the validator accepts a `Claim` over `mkClaimCtx` with the beneficiary key
signed and a well-formed schedule, then the continuing output reproduces the
datum and keeps at least the required remainder of the asset (spec §9 R2/R3,
I2/I3). The output's datum/value are free, so accepting *forces* them. -/
theorem claim_sound_partial
    (validator : Program)
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
    validatorAccepts ctx validator →
      -- continuation reproduces the datum (I3) ...
      outDatum = datumData d ∧
      -- ... and keeps the required remainder (I2/B1).
      outQty ≥ required a.total d.startTime d.endTime now := by
  -- TODO: prove with `blaster` once `validRangeData` is real and the toolchain
  -- is available. Cannot be claimed sound until then.
  sorry

/-- **Cancel soundness.** A `Cancel` that the validator accepts implies the
schedule ordering and `now > recovery_time` (strict; spec §9 R6, C7).
TODO: state over a cancel context and prove. -/
theorem cancel_sound (_validator : Program) (_d : VestingDatum) :
    True := by
  -- TODO: build a cancel context (locker authorized, no continuation) and
  -- conclude `validSchedule d ∧ recovery_time < now`. Placeholder.
  trivial

end Formal.Vesting.Linear.Soundness

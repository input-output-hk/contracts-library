import Formal.TxModels.VestingTypes

/-! Experimental vesting cancel model from PR #55 at f5cbda7df624f2496dd2e6fe354a0cd15365b923. -/

namespace Formal.TxModels.TxM008

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.TxModels.TxBuilder
open Formal.TxModels.Vesting

structure CancelLeaves where
  beneficiary : ByteString
  locker : ByteString
  name : ByteString
  total : Int
  start : Int
  finish : Int
  recovery : Int
  script : ByteString
  prevTx : ByteString
  txId : ByteString
  scriptAda : Int
  feeInputAda : Int
  fee : Int
  now : Int
  signer : ByteString

def cancel (p : CancelLeaves) : ScriptContext :=
  let datum := vestingDatum p.beneficiary p.locker p.name p.total p.start p.finish p.recovery
  let position := input p.prevTx 0 (toScript p.script (adaAnd p.scriptAda vestedPolicy p.name p.total) datum)
  let feeInput := input p.prevTx 1 (toKey p.signer (ada p.feeInputAda))
  let change := p.scriptAda + p.feeInputAda - p.fee
  let back := toKey p.signer (adaAnd change vestedPolicy p.name p.total)
  Spend.context
    { own := position
      others := [feeInput]
      outputs := [back]
      signatories := [p.signer]
      validFrom := p.now
      fee := p.fee
      txId := p.txId
      redeemer := toData Vesting.Types.VestingRedeemer.Cancel }

def metadata : Metadata := {
  id := "TxM-008"
  title := "Experimental vesting Cancel context"
  plutus_version := "v3"
  description := "Baseline Cancel contexts for the pinned linear-vesting test profile. Two inputs spend the vesting position and the signer's ADA; one output returns the vested asset and ADA change to the signer. There is exactly one signer and one vested asset under the fixed policy policyA. Keys, amounts, times, and other leaf values vary. The model uses the typed Cancel redeemer and a vesting datum with key credentials. It constructs ADA change as input ADA minus the fee. Reference inputs, mint, certificates, withdrawals, votes, proposals, and the datum map are empty; the validity interval has a lower bound and no upper bound." }

end Formal.TxModels.TxM008

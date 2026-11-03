import Formal.TxModels.VestingTypes

/-! Experimental vesting claim model from PR #55 at f5cbda7df624f2496dd2e6fe354a0cd15365b923. -/

namespace Formal.TxModels.TxM007

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.TxModels.TxBuilder
open Formal.TxModels.Vesting

structure ClaimLeaves where
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
  keptAda : Int
  kept : Int
  fee : Int
  now : Int
  signer : ByteString

def claim (p : ClaimLeaves) : ScriptContext :=
  let datum := vestingDatum p.beneficiary p.locker p.name p.total p.start p.finish p.recovery
  let position := input p.prevTx 0 (toScript p.script (adaAnd p.scriptAda vestedPolicy p.name p.total) datum)
  let feeInput := input p.prevTx 1 (toKey p.signer (ada p.feeInputAda))
  let continuation := toScript p.script (adaAnd p.keptAda vestedPolicy p.name p.kept) datum
  let change := p.scriptAda + p.feeInputAda - p.keptAda - p.fee
  let payout := toKey p.signer (adaAnd change vestedPolicy p.name (p.total - p.kept))
  Spend.context
    { own := position
      others := [feeInput]
      outputs := [continuation, payout]
      signatories := [p.signer]
      validFrom := p.now
      fee := p.fee
      txId := p.txId
      redeemer := toData Vesting.Types.VestingRedeemer.Claim }

def metadata : Metadata := {
  id := "TxM-007"
  title := "Experimental vesting Claim context"
  plutus_version := "v3"
  description := "Baseline Claim contexts for the pinned linear-vesting test profile. Two inputs spend the vesting position and the signer's ADA; two outputs continue the position and pay the signer. There is exactly one signer and one vested asset under the fixed policy policyA. Keys, amounts, times, and other leaf values vary. The model uses the typed Claim redeemer and a vesting datum with key credentials. It constructs the asset payout as total minus kept and the ADA change from inputs minus continuation and fee. Reference inputs, mint, certificates, withdrawals, votes, proposals, and the datum map are empty; the validity interval has a lower bound and no upper bound." }

end Formal.TxModels.TxM007

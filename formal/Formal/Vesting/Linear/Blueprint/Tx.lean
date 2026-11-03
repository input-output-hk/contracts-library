-- The honest transactions for the checks in `Checks.lean`: for each action, a shape, that is a
-- transaction with a fixed structure whose leaves are the fields of a structure. Written once by
-- process_blueprint.py as a stub; it is never replaced, so edit it freely.
import CardanoLedgerApi
import Formal.Universal.Properties
import Formal.Vesting.Linear.Blueprint.Types

namespace Formal.Vesting.Linear.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.Universal.TxBuilder

/-- The policy of the vested asset. A literal: a symbolic policy stops Blaster inside
    `validScriptContext` (docs/Universal/DEAD_ENDS.md §17). -/
def vestedPolicy : ByteString := "policyA"

/-- The datum: one vested asset, key credentials for the beneficiary and the locker. -/
def vestingDatum (beneficiary locker name : ByteString) (total start finish recovery : Int) : Data :=
  toData
    ({ beneficiary := .PubKeyCredential beneficiary
       locker := .PubKeyCredential locker
       vesting := [{ policy := vestedPolicy, name := name, total := total }]
       start_time := start
       end_time := finish
       recovery_time := recovery } : Vesting.Types.VestingDatum)

/-! ## claim: the position and the signer's ada in; the position, with `kept` of the asset left,
back to the script, and the rest to the signer out; one signatory. -/

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

/-! ## cancel: the position and the signer's ada in; everything to the signer out; one
signatory. -/

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

end Formal.Vesting.Linear.Blueprint

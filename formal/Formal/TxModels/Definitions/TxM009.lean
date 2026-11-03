import Formal.TxModels.Common
import Formal.TxModels.Requirements
import Formal.TxModels.Runnable

namespace Formal.TxModels.TxM009

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.TxModels.TxBuilder

def inputs : SpendingInputs := {
  datum := .constr 0 [.bytes]
  redeemer := .constr 0 [] }

structure SpendLeaves where
  owner : ByteString
  signer : ByteString
  recipient : ByteString
  script : ByteString
  prevTx : ByteString
  txId : ByteString
  inputAda : Int
  fee : Int
  validFrom : Int

def spend (p : SpendLeaves) : ScriptContext :=
  let own := input p.prevTx 0 (toScript p.script (ada p.inputAda) (.Constr 0 [.B p.owner]))
  Spend.context
    { own := own
      outputs := [toKey p.recipient (ada (p.inputAda - p.fee))]
      signatories := [p.signer]
      validFrom := p.validFrom
      fee := p.fee
      txId := p.txId
      redeemer := .Constr 0 [] }

def metadata : Metadata := {
  id := "TxM-009"
  title := "Single-signer key-datum spend"
  plutus_version := "v3"
  description := "Spending contexts with one script input at output index zero, one public-key output, and exactly one signer. The input holds only ADA and the inline datum Constr 0 [B owner]; the redeemer is Constr 0 []. The output holds input ADA minus the fee and has no datum. Owner, signer, recipient, script hash, previous transaction ID, transaction ID, input ADA, fee, and validity lower bound vary independently. Addresses have no staking credentials; outputs have no reference scripts. Reference inputs, mint, certificates, withdrawals, votes, proposals, and the datum map are empty; treasury fields are absent. The validity interval has a lower bound and no upper bound." }

/-- Structural admission reuses the model's declared input requirements. -/
def runnable : Runnable := { metadata, context := ``spend, admission := .spending inputs }

end Formal.TxModels.TxM009

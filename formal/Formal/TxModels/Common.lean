import Lean.Data.Json
import CardanoLedgerApi

namespace Formal.TxModels

/-- The four descriptive fields maintained beside each runnable model. -/
structure Metadata where
  id : String
  title : String
  plutus_version : String
  description : String

def Metadata.toJson (metadata : Metadata) : Lean.Json := Lean.Json.mkObj [
  ("id", .str metadata.id), ("title", .str metadata.title),
  ("plutus_version", .str metadata.plutus_version), ("description", .str metadata.description)]

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

def mkCtx (txInfo : TxInfo) (red : Redeemer) (scInfo : ScriptInfo) : ScriptContext :=
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := red
    scriptContextScriptInfo := scInfo }

end Formal.TxModels

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3

namespace Formal.TxModels.TxBuilder

/-- `lovelace` ada and nothing else. -/
def ada (lovelace : Int) : Value :=
  [(.B "", .Map [(.B "", .I lovelace)])]

/-- `lovelace` ada and `qty` of one asset. -/
def adaAnd (lovelace : Int) (policy name : ByteString) (qty : Int) : Value :=
  [(.B "", .Map [(.B "", .I lovelace)]), (.B policy, .Map [(.B name, .I qty)])]

def keyAddress (key : ByteString) : Address := ⟨.PubKeyCredential key, none⟩

def scriptAddress (hash : ByteString) : Address := ⟨.ScriptCredential hash, none⟩

/-- An output to a key address, with no datum. -/
def toKey (key : ByteString) (value : Value) : TxOut :=
  ⟨keyAddress key, value, .NoOutputDatum, none⟩

/-- An output to a script address, with an inline datum. -/
def toScript (hash : ByteString) (value : Value) (datum : Data) : TxOut :=
  ⟨scriptAddress hash, value, .OutputDatum datum, none⟩

/-- An input: the output `out`, created by transaction `tx` at position `index`. -/
def input (tx : ByteString) (index : Int) (out : TxOut) : TxInInfo :=
  ⟨⟨tx, index⟩, out⟩

/-- A spend of `own`, with `others` as the remaining inputs, in that order. -/
structure Spend where
  own : TxInInfo
  others : List TxInInfo := []
  outputs : List TxOut
  signatories : List ByteString := []
  /-- The transaction is valid from this time on, with no upper bound. -/
  validFrom : Int
  fee : Int
  txId : ByteString
  redeemer : Data

/-- The script context of `s`. The datum passed to the script is `own`'s inline datum, if it has
    one; the redeemer is recorded for `own`. -/
def Spend.context (s : Spend) : ScriptContext :=
  let datum := match s.own.txInInfoResolved.txOutDatum with
    | .OutputDatum d => some d
    | _ => none
  { scriptContextTxInfo :=
      { txInfoInputs := s.own :: s.others
        txInfoReferenceInputs := []
        txInfoOutputs := s.outputs
        txInfoFee := s.fee
        txInfoMint := []
        txInfoTxCerts := []
        txInfoWdrl := []
        txInfoValidRange := IsData.toData (CardanoLedgerApi.V1.Time.after s.validFrom)
        txInfoSignatories := s.signatories
        txInfoRedeemers := [(.Spending s.own.txInInfoOutRef, s.redeemer)]
        txInfoData := []
        txInfoId := s.txId
        txInfoVotes := []
        txInfoProposalProcedures := []
        txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
        txInfoTreasuryDonation := IsData.toData (none : Option Int) }
    scriptContextRedeemer := s.redeemer
    scriptContextScriptInfo := .SpendingScript s.own.txInInfoOutRef datum }

end Formal.TxModels.TxBuilder

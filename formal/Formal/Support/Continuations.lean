import CardanoLedgerApi

namespace Formal.Support.Continuations

open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.V3

def withOutputs (h : ScriptContext) (outs : List TxOut) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoOutputs := outs } }

def keyAddr (h : PubKeyHash) : Address := ⟨.PubKeyCredential h, none⟩

/-- The input being spent, if the context is a spend and the input is in the transaction. -/
def ownInput? (ctx : ScriptContext) : Option TxInInfo :=
  match ctx.scriptContextScriptInfo with
  | .SpendingScript ref _ => ctx.scriptContextTxInfo.txInfoInputs.find? (fun i => i.txInInfoOutRef == ref)
  | _ => none

/-- The original candidate's fixed destination key. -/
def attackerKey : ByteString := "61747461636b6572"

/-- Redirect every output matching the spent input's payment credential and remove its datum. -/
def redirectContinuations (h : ScriptContext) : ScriptContext :=
  match ownInput? h with
  | some i =>
      withOutputs h (List.map (fun (o : TxOut) =>
        if o.txOutAddress.addressCredential == i.txInInfoResolved.txOutAddress.addressCredential then
          { o with txOutAddress := keyAddr attackerKey, txOutDatum := .NoOutputDatum }
        else o) h.scriptContextTxInfo.txInfoOutputs)
  | none => h

/-- Match continuations by the spent input's payment credential alone. -/
def isContinuation (h : ScriptContext) (o : TxOut) : Bool :=
  match ownInput? h with
  | some i => o.txOutAddress.addressCredential == i.txInInfoResolved.txOutAddress.addressCredential
  | none => false

/-- Apply `f` to the first output satisfying `p`. -/
def changeFirst (p : TxOut → Bool) (f : TxOut → TxOut) : List TxOut → List TxOut
  | [] => []
  | o :: os => if p o then f o :: os else o :: changeFirst p f os

/-- Apply `f` to the first continuation only. -/
def changeContinuation (h : ScriptContext) (f : TxOut → TxOut) : ScriptContext :=
  withOutputs h (changeFirst (isContinuation h) f h.scriptContextTxInfo.txInfoOutputs)

/-- The first output matching the spent input's payment credential, if any. -/
def firstContinuation? (h : ScriptContext) : Option TxOut :=
  h.scriptContextTxInfo.txInfoOutputs.find? (isContinuation h)

end Formal.Support.Continuations

import Formal.Support.Compatibility

/-! Shared legacy candidate helpers consolidated from these fork PR snapshots:
- PR #21: b1b7e5c745ad3729b8a7e36347dc183a3eeb45fc
- PR #57: 14d5dd39c04f36e5c0666f047a0d9172a38b3acc
- PR #58: 0e5fb61615af3cf842362341b0de07bc05c2fd06
- PR #59: d983a090b75aff4f22d82a6d1e82611ea332a3c9
- PR #60: 63c8ecce21de8897c252b6563ac90b2ccba343ed
- PR #61: df712cb869e1cf67537ef0c0f7b1241aaae5fa65
- PR #62: 7c5dce717ca1d2b1d975c1c1b044bc48c07e0687

The definitions retain their original bodies under the shared support namespace.
The `redirectOutputs` comment describes only that particular mutation.
-/

namespace Formal.Support

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.V3

def withRange (h : ScriptContext) (r : Data) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoValidRange := r } }

/-- The validity range (−∞, +∞), as ledger `Data`. -/
def rangeAlways : Data :=
  .Constr 0 [.Constr 0 [.Constr 0 [], .Constr 1 []], .Constr 0 [.Constr 2 [], .Constr 1 []]]

def outputsOf (h : ScriptContext) : List TxOut := h.scriptContextTxInfo.txInfoOutputs

def withOutputs (h : ScriptContext) (outs : List TxOut) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoOutputs := outs } }

/-- `h` with its first output moved to the end. -/
def rotateOutputs (h : ScriptContext) : ScriptContext :=
  match h.scriptContextTxInfo.txInfoOutputs with
  | [] => h
  | o :: os => withOutputs h (List.append os [o])

def keyAddr (h : PubKeyHash) : Address := ⟨.PubKeyCredential h, none⟩

/-- The input being spent, if the context is a spend and the input is in the transaction. -/
def ownInput? (ctx : ScriptContext) : Option TxInInfo :=
  match ctx.scriptContextScriptInfo with
  | .SpendingScript ref _ => ctx.scriptContextTxInfo.txInfoInputs.find? (fun i => i.txInInfoOutRef == ref)
  | _ => none

/-- The key that receives redirected or pocketed value. -/
def attackerKey : ByteString := "61747461636b6572"

/-- `h` with every output back to the script sent to `attackerKey` instead, without a datum.
    "The member needs its continuations" is that this is rejected. -/
def redirectContinuations (h : ScriptContext) : ScriptContext :=
  match ownInput? h with
  | some i =>
      withOutputs h (List.map (fun (o : TxOut) =>
        if o.txOutAddress.addressCredential == i.txInInfoResolved.txOutAddress.addressCredential then
          { o with txOutAddress := keyAddr attackerKey, txOutDatum := .NoOutputDatum }
        else o) h.scriptContextTxInfo.txInfoOutputs)
  | none => h

/-- Whether `o` goes back to the script: it has the payment credential of the input being spent. -/
def isContinuation (h : ScriptContext) (o : TxOut) : Bool :=
  match ownInput? h with
  | some i => o.txOutAddress.addressCredential == i.txInInfoResolved.txOutAddress.addressCredential
  | none => false

/-- `outs` with `f` applied to the first output satisfying `p`. -/
def changeFirst (p : TxOut → Bool) (f : TxOut → TxOut) : List TxOut → List TxOut
  | [] => []
  | o :: os => if p o then f o :: os else o :: changeFirst p f os

/-- `h` with `f` applied to its first output back to the script. With `reverseOutputs` and `rotateOutputs` checking that the
    order of outputs does not matter, this stands for any output back to the script. -/
def changeContinuation (h : ScriptContext) (f : TxOut → TxOut) : ScriptContext :=
  withOutputs h (changeFirst (isContinuation h) f h.scriptContextTxInfo.txInfoOutputs)

/-- The first output back to the script, if any. -/
def firstContinuation? (h : ScriptContext) : Option TxOut :=
  h.scriptContextTxInfo.txInfoOutputs.find? (isContinuation h)

/-- The key of inputs and outputs unrelated to the script. -/
def unrelatedKey : ByteString := "756e72656c61746564"

/-- A policy that sorts after the policies of real values, so that a junk token appended at the end
    of a value keeps it sorted. -/
def lastPolicy : ByteString := "zzzzjunk"

/-- `h` with a new input `r` at `unrelatedKey` holding `a` lovelace and one junk token; the junk token
    is appended to its first output back to the script, and the lovelace goes to a new output at
    `unrelatedKey`. -/
def addJunkFrom (h : ScriptContext) (r : TxOutRef) (a : Int) : ScriptContext :=
  let junk : Data × Data := (.B lastPolicy, .Map [(.B lastPolicy, .I 1)])
  let info := h.scriptContextTxInfo
  let h' := { h with scriptContextTxInfo := { info with
    txInfoInputs := List.append info.txInfoInputs
      [⟨r, ⟨keyAddr unrelatedKey, [(.B "", .Map [(.B "", .I a)]), junk], .NoOutputDatum, none⟩⟩]
    txInfoOutputs := List.append info.txInfoOutputs
      [⟨keyAddr unrelatedKey, [(.B "", .Map [(.B "", .I a)])], .NoOutputDatum, none⟩] } }
  changeContinuation h' (fun o => { o with txOutValue := List.append o.txOutValue [junk] })

/-- `h` with every output sent to `attackerKey` instead, without a datum. In `doubleSatisfaction`, a run that still
    accepts this one redirected variant need not accept other output changes. -/
def redirectOutputs (h : ScriptContext) : ScriptContext :=
  withOutputs h (List.map (fun (o : TxOut) =>
    { o with txOutAddress := keyAddr attackerKey, txOutDatum := .NoOutputDatum })
    h.scriptContextTxInfo.txInfoOutputs)

/-- `h` with the input that `g` spends added under `r`, with `g`'s redeemer recorded for it, and its
    value sent to `attackerKey`: one set of outputs for two script inputs. -/
def addSpendOf (h g : ScriptContext) (r : TxOutRef) : ScriptContext :=
  match ownInput? g with
  | some i =>
      let info := h.scriptContextTxInfo
      { h with scriptContextTxInfo := { info with
          txInfoInputs := List.append info.txInfoInputs [⟨r, i.txInInfoResolved⟩]
          txInfoOutputs := List.append info.txInfoOutputs
            [⟨keyAddr attackerKey, i.txInInfoResolved.txOutValue, .NoOutputDatum, none⟩]
          txInfoRedeemers := List.append info.txInfoRedeemers [(.Spending r, g.scriptContextRedeemer)] } }
  | none => h

/-- `h` as seen by the run of the script for the input `r`, which `g` spent with its datum and
    redeemer. -/
def asSpendOf (h g : ScriptContext) (r : TxOutRef) : ScriptContext :=
  match g.scriptContextScriptInfo with
  | .SpendingScript _ d => { h with scriptContextRedeemer := g.scriptContextRedeemer
                                    scriptContextScriptInfo := .SpendingScript r d }
  | _ => h

end Formal.Support

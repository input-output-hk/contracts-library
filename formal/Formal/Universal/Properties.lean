import PlutusCore.UPLC
import CardanoLedgerApi

/-! Execution and script-context helpers used by generated blueprint checks.
Extracted from fork PR #44 at 99a5734f0e036b6abfb4c3f121a298e35fa2eff6.
-/

namespace Formal.Universal.Properties

open PlutusCore.UPLC.Term (Program Term Const)
open PlutusCore.UPLC.CekMachine (State step initialState applyParams)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3

/-- CEK step bound used by generated checks; not a ledger CPU or memory budget. -/
abbrev ledgerFuel : Nat := 1000000

/-- `none` means the step bound was exhausted before a halt or error. -/
def runFor : State → Nat → Option State
  | .Halt v, _ => some (.Halt v)
  | .Error, _ => some .Error
  | _, 0 => none
  | s, n + 1 => runFor (step default s) n

/-- Error or a non-unit halt within `fuel` steps. Exhaustion is not rejection. -/
def rejectedWithin (p : Program) (args : List Term) (fuel : Nat) : Prop :=
  match p with
  | .Program _ body =>
      match runFor (initialState (applyParams body args)) fuel with
      | some .Error => True
      | some (.Halt v) => v ≠ .VCon Const.Unit
      | _ => False

/-! Context builders leave the full transaction and purpose fields open. -/

def mkCtx (txInfo : TxInfo) (red : Redeemer) (scInfo : ScriptInfo) : ScriptContext :=
  { scriptContextTxInfo := txInfo
    scriptContextRedeemer := red
    scriptContextScriptInfo := scInfo }

structure EverySpend where
  txInfo : TxInfo
  ref : TxOutRef
  datum : Option Datum

def EverySpend.ctx (t : EverySpend) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.SpendingScript t.ref t.datum)

structure EveryMint where
  txInfo : TxInfo
  policy : CurrencySymbol

def EveryMint.ctx (t : EveryMint) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.MintingScript t.policy)

structure EveryWithdraw where
  txInfo : TxInfo
  cred : Credential

def EveryWithdraw.ctx (t : EveryWithdraw) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.RewardingScript t.cred)

structure EveryPublish where
  txInfo : TxInfo
  idx : Int
  cert : TxCert

def EveryPublish.ctx (t : EveryPublish) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.CertifyingScript t.idx t.cert)

structure EveryVote where
  txInfo : TxInfo
  voter : Voter

def EveryVote.ctx (t : EveryVote) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.VotingScript t.voter)

structure EveryPropose where
  txInfo : TxInfo
  idx : Int
  proposal : ProposalProcedure

def EveryPropose.ctx (t : EveryPropose) (r : Data) : ScriptContext :=
  mkCtx t.txInfo r (.ProposingScript t.idx t.proposal)

def signatoriesOf (h : ScriptContext) : List PubKeyHash := h.scriptContextTxInfo.txInfoSignatories

def withSignatories (h : ScriptContext) (sigs : List PubKeyHash) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoSignatories := sigs } }

end Formal.Universal.Properties

/-!
# Building script contexts

Validator-independent builders for the honest transactions in each validator's `Tx.lean`. Any
argument may be a variable, so that a shape can leave every leaf symbolic. `Spend` adds the
bookkeeping the ledger model requires; inputs are taken in the order given, so the caller keeps
them sorted by reference.
-/

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3

namespace Formal.Universal.TxBuilder

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

end Formal.Universal.TxBuilder

namespace Formal.Universal.Properties

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

end Formal.Universal.Properties

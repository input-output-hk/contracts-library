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

import PlutusCore.UPLC
import CardanoLedgerApi.V3
import CardanoLedgerApi.V1.Time

/-!
# Proof harness: composable builders (experiment)

Small builders over the ledger types. Each takes its open values as arguments, so a transaction
is a composition of pieces, the way an Aiken fuzzer composes `fuzz.list(fuzz.int())`. Nothing
here draws values: a property quantifies over the arguments, and Blaster fills them.

A Bool argument named like a presence flag (`b`, `b1`, `toOwn`) selects whether an item is in
the transaction or where it goes. Lists are bounded: `upTo2` holds at most two items.
-/

namespace Universal.Harness

open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address ScriptContext ScriptPurpose TxInfo TxInInfo TxOut Value)
open CardanoLedgerApi.V1.Time (POSIXTimeRange after everything)

/-- At most one item: present when the flag is true. -/
def optList {α : Type} (b : Bool) (x : α) : List α := if b then [x] else []

/-- Up to two items, each with its own presence flag. -/
def upTo2 {α : Type} (b1 b2 : Bool) (x1 x2 : α) : List α := optList b1 x1 ++ optList b2 x2

/-- A value holding only lovelace. -/
def ada (lovelace : Int) : Value := [(Data.B "", Data.Map [(Data.B "", Data.I lovelace)])]

/-- At most one minted asset. -/
def token (present : Bool) (policy name : ByteString) (qty : Int) : List (Data × Data) :=
  optList present (Data.B policy, Data.Map [(Data.B name, Data.I qty)])

def keyAddress (h : ByteString) : Address := ⟨.PubKeyCredential h, none⟩
def scriptAddress (h : ByteString) : Address := ⟨.ScriptCredential h, none⟩

/-- One of three destinations: the own script, another script, or a key. -/
def destination (toOwn toForeign : Bool) (own other : ByteString) : Address :=
  if toOwn then scriptAddress own else if toForeign then scriptAddress other else keyAddress other

/-- An input locked at the own script, with an inline datum. -/
def scriptInput (ref : CardanoLedgerApi.V3.TxOutRef) (own : ByteString) (v : Value) (d : Data) : TxInInfo :=
  ⟨ref, ⟨scriptAddress own, v, .OutputDatum d, none⟩⟩

/-- An output carrying an inline datum. -/
def outputWithDatum (a : Address) (v : Value) (d : Data) : TxOut := ⟨a, v, .OutputDatum d, none⟩

/-- An output with no datum: a plain payment. -/
def payment (a : Address) (v : Value) : TxOut := ⟨a, v, .NoOutputDatum, none⟩

/-- A validity range with a finite start, or no limit at all. -/
def validity (finite : Bool) (lo : Int) : POSIXTimeRange := if finite then after lo else everything

/-- A transaction body from its parts; the fields the harness does not cover are empty. -/
def tx (ins : List TxInInfo) (outs : List TxOut) (fee : Int) (mint : List (Data × Data))
    (range : POSIXTimeRange) (sigs : List ByteString) (rdmrs : List (ScriptPurpose × Data)) : TxInfo :=
  { txInfoInputs := ins
    txInfoReferenceInputs := []
    txInfoOutputs := outs
    txInfoFee := fee
    txInfoMint := mint
    txInfoTxCerts := []
    txInfoWdrl := []
    txInfoValidRange := IsData.toData range
    txInfoSignatories := sigs
    txInfoRedeemers := rdmrs
    txInfoData := []
    txInfoId := "txid_placeholder_32bytes!!!!!!!!"
    txInfoVotes := []
    txInfoProposalProcedures := []
    txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
    txInfoTreasuryDonation := IsData.toData (none : Option Int) }

/-- The script spending input `ref` with datum `d` and redeemer `r`. -/
def spending (t : TxInfo) (ref : CardanoLedgerApi.V3.TxOutRef) (d r : Data) : ScriptContext :=
  { scriptContextTxInfo := t
    scriptContextRedeemer := r
    scriptContextScriptInfo := .SpendingScript ref (some d) }

end Universal.Harness

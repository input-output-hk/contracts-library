import Formal.Support.Continuations

namespace Formal.Properties.Universal.UP008

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.V3 (ScriptContext TxOutRef)
open Formal.Support.Continuations

/-- The original candidate's fixed key for the appended input and output. -/
def unrelatedKey : ByteString := "756e72656c61746564"

/-- The original candidate's fixed junk policy and asset name. -/
def lastPolicy : ByteString := "zzzzjunk"

/-- Append an input funding one fixed junk asset and `a` lovelace, return the lovelace
    in a new output, and append the junk asset to the first continuation's value. -/
def addJunkFrom (h : ScriptContext) (r : TxOutRef) (a : Int) : ScriptContext :=
  let junk : Data × Data := (.B lastPolicy, .Map [(.B lastPolicy, .I 1)])
  let info := h.scriptContextTxInfo
  let h' := { h with scriptContextTxInfo := { info with
    txInfoInputs := List.append info.txInfoInputs
      [⟨r, ⟨keyAddr unrelatedKey, [(.B "", .Map [(.B "", .I a)]), junk], .NoOutputDatum, none⟩⟩]
    txInfoOutputs := List.append info.txInfoOutputs
      [⟨keyAddr unrelatedKey, [(.B "", .Map [(.B "", .I a)])], .NoOutputDatum, none⟩] } }
  changeContinuation h' (fun o => { o with txOutValue := List.append o.txOutValue [junk] })

/-- Adding one fixed junk asset to the first continuation requires rejection under four guards. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p (r : TxOutRef) (a : Int),
    valid (context p) = true →
    accepts (context p) →
    rejects (redirectContinuations (context p)) →
    valid (addJunkFrom (context p) r a) = true →
    rejects (addJunkFrom (context p) r a)

/-- A context, input reference, and lovelace amount satisfying all four guards witness applicability. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, ∃ (r : TxOutRef), ∃ (a : Int),
    valid (context p) = true ∧
    accepts (context p) ∧
    rejects (redirectContinuations (context p)) ∧
    valid (addJunkFrom (context p) r a) = true

end Formal.Properties.Universal.UP008

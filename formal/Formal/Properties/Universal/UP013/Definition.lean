import CardanoLedgerApi

namespace Formal.Properties.Universal.UP013

open CardanoLedgerApi.V3 (ScriptContext)
open PlutusCore.Data (Data)

/-- Replace only the validity range, preserving every other context field. -/
def withRange (h : ScriptContext) (r : Data) : ScriptContext :=
  { h with scriptContextTxInfo := { h.scriptContextTxInfo with txInfoValidRange := r } }

/-- The validity range `(-∞, +∞)`, with the original candidate's ledger encoding. -/
def rangeAlways : Data :=
  .Constr 0 [.Constr 0 [.Constr 0 [], .Constr 1 []], .Constr 0 [.Constr 2 [], .Constr 1 []]]

/-- Replacing the validity range with `(-∞, +∞)` requires rejection under these premises. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p,
    valid (context p) = true →
    accepts (context p) →
    valid (withRange (context p) rangeAlways) = true →
    rejects (withRange (context p) rangeAlways)

/-- A valid accepted baseline and a valid changed context witness applicability. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p,
    valid (context p) = true ∧
    accepts (context p) ∧
    valid (withRange (context p) rangeAlways) = true

end Formal.Properties.Universal.UP013

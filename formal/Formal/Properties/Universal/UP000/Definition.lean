import CardanoLedgerApi

namespace Formal.Properties.Universal.UP000

open CardanoLedgerApi.V3 (ScriptContext)

/-- A model-valid accepted context exists in the supplied context family. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, valid (context p) = true ∧ accepts (context p)

end Formal.Properties.Universal.UP000

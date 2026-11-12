import CardanoLedgerApi

namespace Formal.Properties.Universal.UP004

open CardanoLedgerApi.V3 (ScriptContext)

/-- A model-valid explicitly rejected context exists in the supplied context family. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p, valid (context p) = true ∧ rejects (context p)

end Formal.Properties.Universal.UP004

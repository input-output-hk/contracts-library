import Formal.Universal.Support.Execution

namespace Formal.Universal.Properties.UP001

open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (ScriptContext)

/-- Nonacceptance over a context family, using the configured evaluator predicate. -/
def statement {A : Type} (accepts : ScriptContext → Prop)
    (context : A → Data → ScriptContext) : Prop :=
  ∀ (r : Data) (t : A), ¬ accepts (context t r)

end Formal.Universal.Properties.UP001

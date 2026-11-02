import Formal.Properties.Universal.UP015.Definition

namespace Formal.Properties.Universal.UP015.Tests.Controls

open CardanoLedgerApi.V3 (ScriptContext)

/-- Test only: require rejection where the real property requires acceptance. -/
def rejectAfterReverse {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p,
    valid (context p) = true →
    accepts (context p) →
    valid (reverseOutputs (context p)) = true →
    rejects (reverseOutputs (context p))

end Formal.Properties.Universal.UP015.Tests.Controls

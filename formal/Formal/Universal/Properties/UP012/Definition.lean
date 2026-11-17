import Formal.Universal.Support.Execution

namespace Formal.Universal.Properties.UP012

open CardanoLedgerApi.V3 (ScriptContext)
open Formal.Universal.Support (signatoriesOf withSignatories)

/-- The primary signer-removal claim, parameterized by a context family and evaluator predicates. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p,
    valid (context p) = true →
    accepts (context p) →
    signatoriesOf (context p) ≠ [] →
    valid (withSignatories (context p) (signatoriesOf (context p)).tail) = true →
    rejects (withSignatories (context p) (signatoriesOf (context p)).tail)

/-- A witness to the premises needed by this property/model application. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p,
    valid (context p) = true ∧
    accepts (context p) ∧
    signatoriesOf (context p) ≠ [] ∧
    valid (withSignatories (context p) (signatoriesOf (context p)).tail) = true

end Formal.Universal.Properties.UP012

import Blaster
import Formal.Settings.Blueprint.MintQuantity

set_option Elab.async false

namespace Tests.UP016

open Formal.Settings.Blueprint
open Formal.Support (ledgerFuel)

/-- Stronger proof obligation: positive delta alone forces explicit bounded rejection.
Removing the original acceptance and model-validity premises strengthens the
obligation. This helper remains unproved until its standalone invocation succeeds.
-/
theorem positiveQuantityIncreaseRejects :
    ∀ (p : MintLeaves) (delta : Int),
      delta > 0 → rejects ledgerFuel (changed p delta) := by
  blaster

#print axioms positiveQuantityIncreaseRejects

-- Derive the original claim without changing any of its guards, model, or bound.
theorem quantityIncreaseRejects_proved : quantityIncreaseRejects := by
  intro p delta positiveDelta _originalValid _originalAccepts _changedValid
  exact positiveQuantityIncreaseRejects p delta positiveDelta

#print axioms quantityIncreaseRejects_proved

end Tests.UP016

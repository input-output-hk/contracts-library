import Blaster
import Formal.Universal.Standalone.Settings.MintQuantity

set_option Elab.async false

namespace Tests.UP016

open Formal.Universal.Standalone.Settings

-- Expected: Valid. This separately checks that every rejection premise is satisfiable.
theorem quantityIncreaseApplies_proved : quantityIncreaseApplies := by
  blaster

#print axioms quantityIncreaseApplies_proved

end Tests.UP016

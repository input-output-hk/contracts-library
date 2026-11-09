import Blaster
import tests.UP006.ModelFacts

set_option Elab.async false

namespace UP006

open Formal.Support (ledgerFuel)
open CardanoLedgerApi.V3 (validScriptContext)

/-- The original claim satisfies the pinned ledger model. -/
theorem originalValid : validScriptContext original = true := by blaster

/-- Moving 2M ada from the payout to the extra output preserves model validity. -/
theorem extraOutputValid : validScriptContext extraOutput = true := by blaster

/-- Acceptance control for the original two-output claim at the unchanged bound. -/
theorem originalAccepted : accepts ledgerFuel original := by blaster

/-- The frozen compiled validator accepts the concrete three-output context. -/
theorem extraOutputAccepted : accepts ledgerFuel extraOutput := by blaster

/-- One concrete model-valid accepted context refutes the unrestricted UP-006 goal.
This is a statement about the pinned model and CEK bound, not ledger reachability. -/
theorem returnDatumFalsified : ¬ returnDatumGoal := by
  exact returnDatumFalsifiedOfWitness extraOutputValid extraOutputAccepted

end UP006

#print axioms UP006.originalValid
#print axioms UP006.originalAccepted
#print axioms UP006.extraOutputValid
#print axioms UP006.extraOutputAccepted
#print axioms UP006.extraOutputPredicateFalse
#print axioms UP006.returnDatumFalsified

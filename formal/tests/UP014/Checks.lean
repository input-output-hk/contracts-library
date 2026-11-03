import Blaster
import Formal.Vesting.Linear.Blueprint.ContinuationOtherDatum

set_option Elab.async false

open Formal.Vesting.Linear.Blueprint

namespace Tests.UP014.Checks

-- Original Claim property and applicability: expected Valid.
theorem claim_rejects_changed_datum : continuationOtherDatum_claim := by blaster
theorem claim_applies : continuationOtherDatum_claim_applies := by blaster

-- Original Cancel property: expected Valid, with no applicable coverage.
theorem cancel_rejects_changed_datum : continuationOtherDatum_cancel := by blaster

#print axioms claim_rejects_changed_datum
#print axioms claim_applies
#print axioms cancel_rejects_changed_datum

-- Expected Falsified. The Cancel shape has no continuation.
-- This diagnostic intentionally causes a nonzero Lean exit status.
example : continuationOtherDatum_cancel_applies := by blaster

end Tests.UP014.Checks

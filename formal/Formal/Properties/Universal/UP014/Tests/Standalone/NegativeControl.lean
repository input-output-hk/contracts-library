import Blaster
import Formal.Properties.Universal.UP014.Tests.Standalone.Support

set_option Elab.async false

open Tests.UP014.Control

namespace Tests.UP014.NegativeControl

-- Expected Falsified: the credential gate accepts the changed datum.
-- A solver counterexample is required; compilation fails intentionally.
example : continuationOtherDatum_claim := by blaster

-- Expected Valid: the unchanged Claim guards remain satisfiable.
theorem claim_applies : continuationOtherDatum_claim_applies := by blaster

#print axioms claim_applies

end Tests.UP014.NegativeControl

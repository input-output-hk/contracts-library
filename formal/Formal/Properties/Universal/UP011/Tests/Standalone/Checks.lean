import Blaster
import Formal.Vesting.Linear.Blueprint.ContinuationElsewhere

set_option Elab.async false
set_option warningAsError true

open Formal.Vesting.Linear.Blueprint

-- Expected: Valid, Valid, Valid, Falsified. Cancel has no applicable coverage.
-- These commands observe propositions; they do not declare failed proofs.
#blaster [continuationElsewhere_claim]
#blaster [continuationElsewhere_claim_applies]
#blaster [continuationElsewhere_cancel]
#blaster (solve-result: 1) [continuationElsewhere_cancel_applies]

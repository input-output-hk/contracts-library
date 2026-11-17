import Blaster
import Formal.Universal.Support.CandidateHelpers
import Formal.Universal.Standalone.LinearVesting.Types
import Formal.Universal.Standalone.LinearVesting.Tx

set_option Elab.async false

namespace Formal.Tests.UP015

open CardanoLedgerApi.V3 (validScriptContext)
open Formal.Universal.Support
open Formal.Universal.Standalone.LinearVesting

/-- TEST ONLY, expected Falsified: demand explicit rejection after reversing Claim outputs.
    Keep the original program, model, validity premises, and 1,000,000-step bound.
    This deliberately false proposition must not compile as a successful proof. -/
theorem claim_reversal_rejection_control :
    ∀ p,
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      validScriptContext (withOutputs (claim p) (outputsOf (claim p)).reverse) = true →
      rejects ledgerFuel (withOutputs (claim p) (outputsOf (claim p)).reverse) := by
  blaster

end Formal.Tests.UP015

import Blaster
import Formal.Universal.Support.CandidateHelpers
import Formal.Universal.Standalone.LinearVesting.Types
import Formal.Universal.Standalone.LinearVesting.Tx

set_option Elab.async false

namespace Formal.Tests.UP015

open CardanoLedgerApi.V3 (validScriptContext)
open Formal.Universal.Support
open Formal.Universal.Standalone.LinearVesting

/-- Additional control: a valid accepted Claim admits a valid, nonidentity reversal.
    This is stronger than the historical applicability formulas in OutputOrder.lean. -/
theorem claim_reversal_changes_outputs_applies :
    ∃ p,
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      validScriptContext (withOutputs (claim p) (outputsOf (claim p)).reverse) = true ∧
      outputsOf (withOutputs (claim p) (outputsOf (claim p)).reverse) ≠
        outputsOf (claim p) := by
  blaster

end Formal.Tests.UP015

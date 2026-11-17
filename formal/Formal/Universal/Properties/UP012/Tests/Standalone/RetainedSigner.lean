import Blaster
import Formal.Universal.Support.Compatibility
import Formal.Universal.Standalone.LinearVesting.Types
import Formal.Universal.Standalone.LinearVesting.Tx

/-! Deliberately false controls for the standalone UP-012 candidate.

Keep the original signer instead of removing it, while retaining the original
validity, acceptance, and nonempty-signer premises. Both claims must be Falsified:
an accepted context cannot also explicitly reject with its signer unchanged.
This file must fail verification and stays outside the Formal library.
-/

set_option Elab.async false

namespace Tests.UP012.RetainedSigner

open CardanoLedgerApi.V3 (validScriptContext)
open Formal.Universal.Support
open Formal.Universal.Standalone.LinearVesting

/-- Expected Falsified: require rejection after retaining the Claim signatory. -/
theorem retainedSigner_claim_control :
    ∀ p : ClaimLeaves,
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      (signatoriesOf (claim p)) ≠ [] →
      validScriptContext (withSignatories (claim p) (signatoriesOf (claim p))) = true →
      rejects ledgerFuel (withSignatories (claim p) (signatoriesOf (claim p))) := by
  blaster

/-- Expected Falsified: require rejection after retaining the Cancel signatory. -/
theorem retainedSigner_cancel_control :
    ∀ p : CancelLeaves,
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      (signatoriesOf (cancel p)) ≠ [] →
      validScriptContext (withSignatories (cancel p) (signatoriesOf (cancel p))) = true →
      rejects ledgerFuel (withSignatories (cancel p) (signatoriesOf (cancel p))) := by
  blaster

end Tests.UP012.RetainedSigner

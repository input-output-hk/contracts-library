import Blaster
import Formal.Universal.Properties
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

/-! Deliberately false controls for the standalone UP-012 candidate.

Keep the original signer instead of removing it, while retaining the original
validity, acceptance, and nonempty-signer premises. Both claims must be Falsified:
an accepted context cannot also explicitly reject with its signer unchanged.
This file must fail verification and stays outside the Formal library.
-/

set_option Elab.async false

namespace Tests.UP012.RetainedSigner

open CardanoLedgerApi.V3 (validScriptContext)
open Formal.Universal.Properties
open Formal.Vesting.Linear.Blueprint

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

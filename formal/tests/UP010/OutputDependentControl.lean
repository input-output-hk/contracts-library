import Blaster
import Formal.Vesting.Linear.Blueprint.Tx
import tests.UP010.OutputDependentFixture

set_option Elab.async false

namespace Tests.UP010.OutputDependentControl

open CardanoLedgerApi.V3 (validScriptContext)
open Formal.Universal.Properties
open Formal.Vesting.Linear.Blueprint (claim)
open Tests.UP010.OutputDependentFixture (accepts rejects)

/-!
Claim-only negative control. The compiled Aiken V3 program requires a script
output. Claim and both combined runs retain one; both redirections remove all
script outputs. Expect Falsified for the unchanged claim, Valid for applicability,
and Valid for the explicit witness. Cancel has no script output and is inapplicable.
The intended Falsified observation makes this file exit unsuccessfully.
-/

/-- The original Claim disjunction: one combined run rejects, or one combined run
    accepts after the specific all-output redirection. -/
theorem doubleSatisfaction_claim :
    ∀ p q r,
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      validScriptContext (claim q) = true →
      accepts ledgerFuel (claim q) →
      validScriptContext (addSpendOf (claim p) (claim q) r) = true →
      (rejects ledgerFuel (addSpendOf (claim p) (claim q) r) ∨
       rejects ledgerFuel (asSpendOf (addSpendOf (claim p) (claim q) r) (claim q) r) ∨
       accepts ledgerFuel (redirectOutputs (addSpendOf (claim p) (claim q) r)) ∨
       accepts ledgerFuel
         (redirectOutputs (asSpendOf (addSpendOf (claim p) (claim q) r) (claim q) r))) := by blaster

/-- `doubleSatisfaction_claim` applies: some valid accepted `claim` transaction gives a valid
    changed transaction, so the check above does not hold only vacuously. -/
theorem doubleSatisfaction_claim_applies :
    ∃ p, ∃ q, ∃ r,
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      validScriptContext (claim q) = true ∧
      accepts ledgerFuel (claim q) ∧
      validScriptContext (addSpendOf (claim p) (claim q) r) = true := by blaster

/-- A model-valid witness has both combined runs accepting and both redirections rejecting. -/
theorem doubleSatisfaction_claim_control_witness :
    ∃ p, ∃ q, ∃ r,
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      validScriptContext (claim q) = true ∧
      accepts ledgerFuel (claim q) ∧
      validScriptContext (addSpendOf (claim p) (claim q) r) = true ∧
      accepts ledgerFuel (addSpendOf (claim p) (claim q) r) ∧
      accepts ledgerFuel (asSpendOf (addSpendOf (claim p) (claim q) r) (claim q) r) ∧
      rejects ledgerFuel (redirectOutputs (addSpendOf (claim p) (claim q) r)) ∧
      rejects ledgerFuel
        (redirectOutputs (asSpendOf (addSpendOf (claim p) (claim q) r) (claim q) r)) := by blaster

end Tests.UP010.OutputDependentControl

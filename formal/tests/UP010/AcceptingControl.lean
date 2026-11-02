import Blaster
import Formal.Universal.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Tx

set_option Elab.async false

namespace Tests.UP010.AcceptingControl

open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Universal.Properties
open Formal.Vesting.Linear.Blueprint (claim cancel)

/-!
Synthetic positive control: a UPLC lambda returning unit. The unchanged UP010
formulas must all be Valid because the acceptance disjuncts hold. This program
is neither an Aiken validator nor a negative control for the retained claim.
-/

def program : Program := .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin program [toTerm ctx] fuel

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

/-- The original Cancel disjunction: one combined run rejects, or one combined run
    accepts after the specific all-output redirection. -/
theorem doubleSatisfaction_cancel :
    ∀ p q r,
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      validScriptContext (cancel q) = true →
      accepts ledgerFuel (cancel q) →
      validScriptContext (addSpendOf (cancel p) (cancel q) r) = true →
      (rejects ledgerFuel (addSpendOf (cancel p) (cancel q) r) ∨
       rejects ledgerFuel (asSpendOf (addSpendOf (cancel p) (cancel q) r) (cancel q) r) ∨
       accepts ledgerFuel (redirectOutputs (addSpendOf (cancel p) (cancel q) r)) ∨
       accepts ledgerFuel (redirectOutputs (asSpendOf (addSpendOf (cancel p) (cancel q) r) (cancel
         q) r))) := by blaster

/-- `doubleSatisfaction_cancel` applies: some valid accepted `cancel` transaction gives a valid
    changed transaction, so the check above does not hold only vacuously. -/
theorem doubleSatisfaction_cancel_applies :
    ∃ p, ∃ q, ∃ r,
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      validScriptContext (cancel q) = true ∧
      accepts ledgerFuel (cancel q) ∧
      validScriptContext (addSpendOf (cancel p) (cancel q) r) = true := by blaster

end Tests.UP010.AcceptingControl

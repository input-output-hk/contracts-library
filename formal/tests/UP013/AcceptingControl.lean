import Blaster
import Formal.Universal.Properties
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

set_option Elab.async false

namespace Formal.Tests.UP013

open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Universal.Properties
open Formal.Vesting.Linear.Blueprint

/-- TEST ONLY: ignore the script context and return unit. -/
def acceptingProgram : Program :=
  .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def controlAccepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram acceptingProgram (args ctx) fuel = .Halt (.VCon Const.Unit)

def controlRejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin acceptingProgram (args ctx) fuel

/-- Expected Falsified: an always-accepting program also accepts the fully unbounded range.
    Keep the original Claim model, premises, mutation, and 1,000,000-step bound. -/
theorem unboundedRange_claim_control :
    ∀ p,
      validScriptContext (claim p) = true →
      controlAccepts ledgerFuel (claim p) →
      validScriptContext (withRange (claim p) rangeAlways) = true →
      controlRejects ledgerFuel (withRange (claim p) rangeAlways) := by blaster

/-- Expected Valid: the Claim control has a valid accepted baseline and a valid mutation. -/
theorem unboundedRange_claim_control_applies :
    ∃ p,
      validScriptContext (claim p) = true ∧
      controlAccepts ledgerFuel (claim p) ∧
      validScriptContext (withRange (claim p) rangeAlways) = true := by blaster

/-- Expected Falsified: an always-accepting program also accepts the fully unbounded range.
    Keep the original Cancel model, premises, mutation, and 1,000,000-step bound. -/
theorem unboundedRange_cancel_control :
    ∀ p,
      validScriptContext (cancel p) = true →
      controlAccepts ledgerFuel (cancel p) →
      validScriptContext (withRange (cancel p) rangeAlways) = true →
      controlRejects ledgerFuel (withRange (cancel p) rangeAlways) := by blaster

/-- Expected Valid: the Cancel control has a valid accepted baseline and a valid mutation. -/
theorem unboundedRange_cancel_control_applies :
    ∃ p,
      validScriptContext (cancel p) = true ∧
      controlAccepts ledgerFuel (cancel p) ∧
      validScriptContext (withRange (cancel p) rangeAlways) = true := by blaster

end Formal.Tests.UP013

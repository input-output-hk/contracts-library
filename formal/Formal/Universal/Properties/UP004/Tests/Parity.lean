import Formal.Universal.Properties.UP004.Definition
import Formal.Universal.Properties.Tests.ParitySupport

/-! Kernel equivalences with the frozen standalone context and evaluator definitions.
Shared test support provides context mappings and evaluators; no solver theorem is imported. -/

namespace Formal.Universal.Properties.UP004.Tests.Parity

open Formal.Universal.Properties.Tests.ParitySupport (claimToLegacy claimFromLegacy cancelToLegacy cancelFromLegacy preparedRejects)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Program Term)
open PlutusCore.UPLC.CekMachine (initialState applyParams)

theorem claimStatement :
    statement validScriptContext
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      ∃ p, validScriptContext (Formal.Universal.Standalone.LinearVesting.claim p) = true ∧
        Formal.Universal.Standalone.LinearVesting.rejects Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.claim p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

theorem cancelStatement :
    statement validScriptContext
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p, validScriptContext (Formal.Universal.Standalone.LinearVesting.cancel p) = true ∧
        Formal.Universal.Standalone.LinearVesting.rejects Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.cancel p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem acceptingPredicateCannotPass {A : Type} (valid : ScriptContext → Bool)
    (context : A → ScriptContext) : ¬ statement valid (fun _ => False) context :=
  fun ⟨_, _, impossible⟩ => impossible

-- CEK step exhaustion is a semantic result, independent of a workflow wall-clock timeout.
theorem zeroFuelExhausts (body : Term) (args : List Term) :
    Formal.Universal.Support.runFor (initialState (applyParams body args)) 0 = none := rfl

theorem zeroFuelCannotReject (program : Program) (args : List Term) :
    ¬ Formal.Universal.Support.rejectedWithin program args 0 := by
  cases program
  exact fun impossible => impossible

theorem zeroFuelCannotEstablishExistence {A : Type} (program : Program)
    (valid : ScriptContext → Bool) (context : A → ScriptContext) :
    ¬ statement valid (preparedRejects program 0) context :=
  fun ⟨p, _, rejected⟩ => zeroFuelCannotReject program [toTerm (context p)] rejected

end Formal.Universal.Properties.UP004.Tests.Parity

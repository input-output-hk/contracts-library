import Formal.Universal.Properties.UP004.Definition
import Formal.Universal.Properties.UP000.Tests.Parity

/-! Kernel equivalences with the frozen standalone context and evaluator definitions.
The context mappings come from UP-000 tests; no historical solver theorem is imported. -/

namespace Formal.Universal.Properties.UP004.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Program Term)
open PlutusCore.UPLC.CekMachine (initialState applyParams)
open UP000.Tests.Parity (claimToLegacy claimFromLegacy cancelToLegacy cancelFromLegacy)

-- Tests.lean checks that generated support and the frozen Types embed the same bytes.
def preparedRejects (program : Program) (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Universal.Support.rejectedWithin program [toTerm ctx] fuel

theorem evaluatorParity (fuel : Nat) (ctx : ScriptContext) :
    preparedRejects Formal.Universal.Standalone.LinearVesting.program fuel ctx ↔
      Formal.Universal.Standalone.LinearVesting.rejects fuel ctx := Iff.rfl

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

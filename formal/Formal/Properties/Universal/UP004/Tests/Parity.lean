import Formal.Properties.Universal.UP004.Definition
import Formal.Properties.Universal.UP000.Tests.Parity

/-! Kernel equivalences with the frozen standalone context and evaluator definitions.
The context mappings come from UP-000 tests; no historical solver theorem is imported. -/

namespace Formal.Properties.Universal.UP004.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Program Term)
open PlutusCore.UPLC.CekMachine (initialState applyParams)
open UP000.Tests.Parity (claimToLegacy claimFromLegacy cancelToLegacy cancelFromLegacy)

-- Tests.lean checks that generated support and the frozen Types embed the same bytes.
def preparedRejects (program : Program) (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Support.rejectedWithin program [toTerm ctx] fuel

theorem evaluatorParity (fuel : Nat) (ctx : ScriptContext) :
    preparedRejects Formal.Vesting.Linear.Blueprint.program fuel ctx ↔
      Formal.Vesting.Linear.Blueprint.rejects fuel ctx := Iff.rfl

theorem claimStatement :
    statement validScriptContext
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      ∃ p, validScriptContext (Formal.Vesting.Linear.Blueprint.claim p) = true ∧
        Formal.Vesting.Linear.Blueprint.rejects Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.claim p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

theorem cancelStatement :
    statement validScriptContext
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p, validScriptContext (Formal.Vesting.Linear.Blueprint.cancel p) = true ∧
        Formal.Vesting.Linear.Blueprint.rejects Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.cancel p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem acceptingPredicateCannotPass {A : Type} (valid : ScriptContext → Bool)
    (context : A → ScriptContext) : ¬ statement valid (fun _ => False) context :=
  fun ⟨_, _, impossible⟩ => impossible

-- CEK step exhaustion is a semantic result, independent of a workflow wall-clock timeout.
theorem zeroFuelExhausts (body : Term) (args : List Term) :
    Formal.Support.runFor (initialState (applyParams body args)) 0 = none := rfl

theorem zeroFuelCannotReject (program : Program) (args : List Term) :
    ¬ Formal.Support.rejectedWithin program args 0 := by
  cases program
  exact fun impossible => impossible

theorem zeroFuelCannotEstablishExistence {A : Type} (program : Program)
    (valid : ScriptContext → Bool) (context : A → ScriptContext) :
    ¬ statement valid (preparedRejects program 0) context :=
  fun ⟨p, _, rejected⟩ => zeroFuelCannotReject program [toTerm (context p)] rejected

end Formal.Properties.Universal.UP004.Tests.Parity

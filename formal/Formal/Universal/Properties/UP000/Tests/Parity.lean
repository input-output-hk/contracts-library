import Formal.Universal.Properties.UP000.Definition
import Formal.Universal.Properties.Tests.ParitySupport

/-! Kernel equivalences with the frozen standalone context and evaluator definitions.
The historical existential proofs are deliberately not imported. -/

namespace Formal.Universal.Properties.UP000.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open CardanoLedgerApi.IsData.Class (toTerm)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

open Formal.Universal.Properties.Tests.ParitySupport

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      ∃ p, validScriptContext (Formal.Universal.Standalone.LinearVesting.claim p) = true ∧
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.claim p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

theorem cancelStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p, validScriptContext (Formal.Universal.Standalone.LinearVesting.cancel p) = true ∧
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.cancel p) :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem rejectingPredicateCannotPass {A : Type} (valid : ScriptContext → Bool)
    (context : A → ScriptContext) : ¬ statement valid (fun _ => False) context :=
  fun ⟨_, _, impossible⟩ => impossible

end Formal.Universal.Properties.UP000.Tests.Parity

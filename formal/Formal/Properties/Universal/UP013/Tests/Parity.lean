import Formal.Properties.Universal.UP013.Definition
import Formal.Properties.Universal.UP004.Tests.Parity
import Formal.Support.CandidateHelpers

/-! Kernel equivalences with the expanded standalone formulas.
The shared test mappings preserve the contexts and evaluators without importing solver theorems. -/

namespace Formal.Properties.Universal.UP013.Tests.Parity

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open UP000.Tests.Parity (claimToLegacy claimFromLegacy cancelToLegacy cancelFromLegacy preparedAccepts)
open UP004.Tests.Parity (preparedRejects)

theorem rangeParity : rangeAlways = Formal.Support.rangeAlways := rfl

theorem mutationParity (ctx : ScriptContext) (range : PlutusCore.Data.Data) :
    withRange ctx range = Formal.Support.withRange ctx range := rfl

theorem mutationPreservesReferenceInputs (ctx : ScriptContext) :
    (withRange ctx rangeAlways).scriptContextTxInfo.txInfoReferenceInputs =
      ctx.scriptContextTxInfo.txInfoReferenceInputs := rfl

theorem restoringRangeRestoresContext (ctx : ScriptContext) :
    withRange (withRange ctx rangeAlways) ctx.scriptContextTxInfo.txInfoValidRange = ctx := rfl

theorem claimHasNoReferenceInputs (p : TxModels.TxM007.ClaimLeaves) :
    (TxModels.TxM007.claim p).scriptContextTxInfo.txInfoReferenceInputs = [] := rfl

theorem cancelHasNoReferenceInputs (p : TxModels.TxM008.CancelLeaves) :
    (TxModels.TxM008.cancel p).scriptContextTxInfo.txInfoReferenceInputs = [] := rfl

theorem claimStatement :
    statement validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      ∀ p,
        validScriptContext (Formal.Vesting.Linear.Blueprint.claim p) = true →
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.claim p) →
        validScriptContext (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.claim p)
          Formal.Support.rangeAlways) = true →
        Formal.Vesting.Linear.Blueprint.rejects Formal.Support.ledgerFuel
          (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.claim p) Formal.Support.rangeAlways) :=
  ⟨fun h p => h (claimFromLegacy p), fun h p => h (claimToLegacy p)⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM007.claim ↔
      ∃ p,
        validScriptContext (Formal.Vesting.Linear.Blueprint.claim p) = true ∧
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.claim p) ∧
        validScriptContext (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.claim p)
          Formal.Support.rangeAlways) = true :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

set_option maxRecDepth 2048 in
theorem cancelStatement :
    statement validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000)
      (preparedRejects Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM008.cancel ↔
      ∀ p,
        validScriptContext (Formal.Vesting.Linear.Blueprint.cancel p) = true →
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.cancel p) →
        validScriptContext (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.cancel p)
          Formal.Support.rangeAlways) = true →
        Formal.Vesting.Linear.Blueprint.rejects Formal.Support.ledgerFuel
          (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.cancel p) Formal.Support.rangeAlways) :=
  ⟨fun h p => h (cancelFromLegacy p), fun h p => h (cancelToLegacy p)⟩

theorem cancelApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Vesting.Linear.Blueprint.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p,
        validScriptContext (Formal.Vesting.Linear.Blueprint.cancel p) = true ∧
        Formal.Vesting.Linear.Blueprint.accepts Formal.Support.ledgerFuel
          (Formal.Vesting.Linear.Blueprint.cancel p) ∧
        validScriptContext (Formal.Support.withRange (Formal.Vesting.Linear.Blueprint.cancel p)
          Formal.Support.rangeAlways) = true :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts context) : statement valid accepts rejects context :=
  fun p original accepted changed => False.elim (absent ⟨p, original, accepted, changed⟩)

end Formal.Properties.Universal.UP013.Tests.Parity

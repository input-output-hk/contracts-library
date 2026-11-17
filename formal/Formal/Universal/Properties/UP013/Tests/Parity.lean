import Formal.Universal.Properties.UP013.Definition
import Formal.Universal.Properties.Tests.ParitySupport
import Formal.Universal.Support.CandidateHelpers

/-! Kernel equivalences with the expanded standalone formulas.
The shared test mappings preserve the contexts and evaluators without importing solver theorems. -/

namespace Formal.Universal.Properties.UP013.Tests.Parity

open Formal.Universal.Properties.Tests.ParitySupport (claimToLegacy claimFromLegacy cancelToLegacy cancelFromLegacy preparedAccepts preparedRejects)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)

theorem rangeParity : rangeAlways = Formal.Universal.Support.rangeAlways := rfl

theorem mutationParity (ctx : ScriptContext) (range : PlutusCore.Data.Data) :
    withRange ctx range = Formal.Universal.Support.withRange ctx range := rfl

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
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      ∀ p,
        validScriptContext (Formal.Universal.Standalone.LinearVesting.claim p) = true →
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.claim p) →
        validScriptContext (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.claim p)
          Formal.Universal.Support.rangeAlways) = true →
        Formal.Universal.Standalone.LinearVesting.rejects Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.claim p) Formal.Universal.Support.rangeAlways) :=
  ⟨fun h p => h (claimFromLegacy p), fun h p => h (claimToLegacy p)⟩

theorem claimApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM007.claim ↔
      ∃ p,
        validScriptContext (Formal.Universal.Standalone.LinearVesting.claim p) = true ∧
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.claim p) ∧
        validScriptContext (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.claim p)
          Formal.Universal.Support.rangeAlways) = true :=
  ⟨fun ⟨p, evidence⟩ => ⟨claimToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨claimFromLegacy p, evidence⟩⟩

set_option maxRecDepth 2048 in
theorem cancelStatement :
    statement validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000)
      (preparedRejects Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM008.cancel ↔
      ∀ p,
        validScriptContext (Formal.Universal.Standalone.LinearVesting.cancel p) = true →
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.cancel p) →
        validScriptContext (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.cancel p)
          Formal.Universal.Support.rangeAlways) = true →
        Formal.Universal.Standalone.LinearVesting.rejects Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.cancel p) Formal.Universal.Support.rangeAlways) :=
  ⟨fun h p => h (cancelFromLegacy p), fun h p => h (cancelToLegacy p)⟩

theorem cancelApplicability :
    applicability validScriptContext
      (preparedAccepts Formal.Universal.Standalone.LinearVesting.program 1000000) TxModels.TxM008.cancel ↔
      ∃ p,
        validScriptContext (Formal.Universal.Standalone.LinearVesting.cancel p) = true ∧
        Formal.Universal.Standalone.LinearVesting.accepts Formal.Universal.Support.ledgerFuel
          (Formal.Universal.Standalone.LinearVesting.cancel p) ∧
        validScriptContext (Formal.Universal.Support.withRange (Formal.Universal.Standalone.LinearVesting.cancel p)
          Formal.Universal.Support.rangeAlways) = true :=
  ⟨fun ⟨p, evidence⟩ => ⟨cancelToLegacy p, evidence⟩,
    fun ⟨p, evidence⟩ => ⟨cancelFromLegacy p, evidence⟩⟩

theorem noApplicabilityMakesStatementVacuous {A : Type} (valid : ScriptContext → Bool)
    (accepts rejects : ScriptContext → Prop) (context : A → ScriptContext)
    (absent : ¬ applicability valid accepts context) : statement valid accepts rejects context :=
  fun p original accepted changed => False.elim (absent ⟨p, original, accepted, changed⟩)

end Formal.Universal.Properties.UP013.Tests.Parity

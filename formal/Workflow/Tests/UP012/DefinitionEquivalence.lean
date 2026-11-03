import Formal.Properties.Universal.UP012.Definition

/-! Frozen expanded formulas from the pre-refactor UP012 declarations.
These kernel-checked equivalences do not invoke the SMT tactic. -/

namespace Workflow.Tests.UP012.DefinitionEquivalence

open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Universal.Properties

variable (accepts rejects : Nat → ScriptContext → Prop)
variable (claim : Formal.TxModels.TxM007.ClaimLeaves → ScriptContext)
variable (cancel : Formal.TxModels.TxM008.CancelLeaves → ScriptContext)

example : (Formal.Properties.Universal.UP012.statement validScriptContext (accepts ledgerFuel) (rejects ledgerFuel) claim) ↔ (∀ p,
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      (signatoriesOf (claim p)) ≠ [] →
      validScriptContext (withSignatories (claim p) (signatoriesOf (claim p)).tail) = true →
      rejects ledgerFuel (withSignatories (claim p) (signatoriesOf (claim p)).tail)) := Iff.rfl

example : (Formal.Properties.Universal.UP012.applicability validScriptContext (accepts ledgerFuel) claim) ↔ (∃ p,
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      (signatoriesOf (claim p)) ≠ [] ∧
      validScriptContext (withSignatories (claim p) (signatoriesOf (claim p)).tail) = true) := Iff.rfl

example : (Formal.Properties.Universal.UP012.statement validScriptContext (accepts ledgerFuel) (rejects ledgerFuel) cancel) ↔ (∀ p,
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      (signatoriesOf (cancel p)) ≠ [] →
      validScriptContext (withSignatories (cancel p) (signatoriesOf (cancel p)).tail) = true →
      rejects ledgerFuel (withSignatories (cancel p) (signatoriesOf (cancel p)).tail)) := Iff.rfl

example : (Formal.Properties.Universal.UP012.applicability validScriptContext (accepts ledgerFuel) cancel) ↔ (∃ p,
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      (signatoriesOf (cancel p)) ≠ [] ∧
      validScriptContext (withSignatories (cancel p) (signatoriesOf (cancel p)).tail) = true) := Iff.rfl

end Workflow.Tests.UP012.DefinitionEquivalence

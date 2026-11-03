import Formal.Properties.Universal.UP015.Definition
import Formal.TxModels.Definitions.TxM007

namespace Workflow.Tests.UP015.DefinitionEquivalence

open CardanoLedgerApi.V3 (ScriptContext TxOut validScriptContext)
open Formal.Properties.Universal.UP015

variable (accepts : ScriptContext → Prop)
variable (claim : Formal.TxModels.TxM007.ClaimLeaves → ScriptContext)

-- Expanded formulas freeze the premises and the actual-change qualification.
example : statement validScriptContext accepts claim ↔ (∀ p,
    validScriptContext (claim p) = true → accepts (claim p) →
    validScriptContext (reverseOutputs (claim p)) = true →
    accepts (reverseOutputs (claim p))) := Iff.rfl

example : applicability validScriptContext accepts claim ↔ (∃ p,
    validScriptContext (claim p) = true ∧ accepts (claim p) ∧
    validScriptContext (reverseOutputs (claim p)) = true ∧
    (reverseOutputs (claim p)).scriptContextTxInfo.txInfoOutputs ≠
      (claim p).scriptContextTxInfo.txInfoOutputs) := Iff.rfl

-- A two-output swap cannot qualify as a no-op when the outputs differ.
example (a b : TxOut) (different : a ≠ b) : [a, b].reverse ≠ [a, b] := by
  intro same
  have swapped : [b, a] = [a, b] := same
  exact different (List.cons.inj swapped).1.symm

example (ctx : ScriptContext) :
    (reverseOutputs ctx).scriptContextScriptInfo = ctx.scriptContextScriptInfo := rfl

end Workflow.Tests.UP015.DefinitionEquivalence

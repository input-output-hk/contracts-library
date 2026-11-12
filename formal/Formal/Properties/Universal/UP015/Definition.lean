import CardanoLedgerApi

namespace Formal.Properties.Universal.UP015

open CardanoLedgerApi.V3 (ScriptContext)

/-- Reverse the output list while preserving every other context field. -/
def reverseOutputs (ctx : ScriptContext) : ScriptContext :=
  { ctx with scriptContextTxInfo :=
      { ctx.scriptContextTxInfo with txInfoOutputs := ctx.scriptContextTxInfo.txInfoOutputs.reverse } }

/-- Output reversal preserves acceptance when both contexts satisfy the supplied validity predicate. -/
def statement {A : Type} (valid : ScriptContext → Bool)
    (accepts : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∀ p,
    valid (context p) = true →
    accepts (context p) →
    valid (reverseOutputs (context p)) = true →
    accepts (reverseOutputs (context p))

/-- A valid accepted context whose reversal is valid and actually changes the output list. -/
def applicability {A : Type} (valid : ScriptContext → Bool)
    (accepts : ScriptContext → Prop) (context : A → ScriptContext) : Prop :=
  ∃ p,
    valid (context p) = true ∧
    accepts (context p) ∧
    valid (reverseOutputs (context p)) = true ∧
    (reverseOutputs (context p)).scriptContextTxInfo.txInfoOutputs ≠
      (context p).scriptContextTxInfo.txInfoOutputs

end Formal.Properties.Universal.UP015

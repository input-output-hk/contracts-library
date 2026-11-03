import Formal.Properties.Universal.UP015.Definition
import Workflow.Declarative.Types

namespace Formal.Properties.Universal.UP015

/-- Reuse the existing Claim model through the shared execution path. -/
def run : Workflow.Declarative.PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Experimental pinned linear-vesting Claim profile only; broader candidate and model design remains open.",
      "Reverses the model's two outputs while preserving the redeemer and other context fields. This covers one swap, not arbitrary output counts or permutations.",
      "Uses the existing one-signer, one-asset Claim geometry and a 1,000,000-step acceptance bound. Model validity and applicability do not establish deployed-ledger reachability.",
      "Applicability requires an accepted model-valid context whose changed output list is different and still model-valid. No duplicate rotation or singleton Cancel check is included.",
      "Index-sensitive protocols may correctly reject a reorder without a corresponding redeemer update; this check is not a universal security requirement."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  theoremPrefix := "reverseOutputs"
  fuel := 1000000
  scope := "Reverse the selected Claim model's two outputs while preserving validScriptContext premises. " ++
    "Require acceptance within 1,000,000 CEK steps. Applicability must establish an actual output-list change. " ++
    "This does not cover arbitrary permutations or establish a universal requirement for index-sensitive validators." }

end Formal.Properties.Universal.UP015

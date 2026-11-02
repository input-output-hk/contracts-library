import Formal.Properties.Universal.UP015.Definition
import Workflow.Declarative.Types

namespace Formal.Properties.Universal.UP015

/-- Reuse the existing Claim model through the shared execution path. -/
def run : Workflow.Declarative.PropertyRun := {
  models := #["TxM-007"]
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

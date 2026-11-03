import Formal.Properties.Universal.UP012.Definition
import Workflow.Declarative.Types

namespace Formal.Properties.Universal.UP012

/-- The model list is the only property/model integration point. -/
def run : Workflow.Declarative.PropertyRun := {
  models := #["TxM-007", "TxM-008", "TxM-009"]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  theoremPrefix := "dropSigner"
  fuel := 1000000
  scope := "Remove the first signer in the selected model; preserve validScriptContext premises. " ++
    "Require explicit rejection within 1,000,000 CEK steps. Applicability is checked separately. " ++
    "This does not establish correct-owner authorization or arbitrary transaction coverage." }

end Formal.Properties.Universal.UP012

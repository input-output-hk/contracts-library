import Formal.Properties.Universal.UP001.Definition
import Workflow.Declarative.Types

namespace Formal.Properties.Universal.UP001

open Workflow Workflow.Declarative

private def skipDeclaredPurpose (target : TargetDescription) (model : Model) :
    Except Generator.Error (Option String) := do
  let some purpose := model.runnable.purpose
    | throw ⟨.invalidPlan, "UP-001 requires a model with a fixed script purpose"⟩
  if target.declaredPurposes.contains purpose then
    return some s!"The selected {purpose.name} purpose has a declared handler; UP-001 has no obligation for this model."
  return none

/-- Enable native purpose models by name; the property owns the undeclared-purpose rule. -/
def run : PropertyRun := {
  models := #["TxM-006", "TxM-001", "TxM-002", "TxM-003", "TxM-004", "TxM-005"]
  statement := { definition := ``statement, arguments := #["(accepts {fuel})"] }
  theoremPrefix := "otherPurpose"
  theoremSuffix := fun model => model.runnable.purpose.map (·.name) |>.getD "unknown"
  skipReason := skipDeclaredPurpose
  fuel := 5000000
  scope := "No acceptance within 5,000,000 CEK steps for undeclared purposes. " ++
    "Fuel exhaustion satisfies the claim; it does not establish explicit rejection." }

end Formal.Properties.Universal.UP001

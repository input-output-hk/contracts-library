import Candidates.UP001
import Workflow.Metadata.Property
import Workflow.Generator.Single

namespace Workflow.Declarative.LegacyUP001

open Workflow Generator

/-- Preserve the existing purpose generator while the other properties use Run.lean. -/
def checks : Array CheckId := Candidates.UP001.modelIds.map fun modelId =>
  { propertyId := "UP-001", definitionVersion := 1, modelId }

def loadCheck (models : Array Formal.TxModels.Metadata) (id : CheckId) :
    IO (Except String ConfiguredCheck) := do
  unless checks.contains id do return .error "unknown legacy UP-001 combination"
  let definition ← match ← PropertyDefinition.readRecord
      "Formal/Properties/Universal/UP001/metadata.json" with
    | .ok value => pure value
    | .error message => return .error message
  let combinations ← match ← CombinedCheck.read "Candidates/combined-checks.json" with
    | .ok value => pure value
    | .error message => return .error message
  return do
    unless definition.id? == some "UP-001" && definition.version? == some 1 do
      throw "legacy UP-001 metadata does not match its implementation"
    if let some primary := definition.primary? then
      unless primary == "Formal.Properties.Universal.UP001.statement" do
        throw "legacy UP-001 metadata names a different primary statement"
    let records ← TransactionModel.parseList (.arr (models.map (·.toJson)))
    let binding ← CheckBinding.resolve definition id.modelId records combinations
    let provider ← Candidates.UP001.providerForModel id.modelId |>.mapError toString
    return { context := { propertyDefinition := definition, binding }, generate := provider.generate }

end Workflow.Declarative.LegacyUP001

import Workflow.Declarative.Types

namespace Workflow.Declarative.Discovery

open Lean

/-- Evaluate actual Run.lean declarations before importing any selected model implementations. -/
def describe (properties : Array Property) (legacyModels : Array String := #[]) : IO UInt32 := do
  let mut descriptions : Array Json := #[]
  let mut models : Array String := #[]
  for property in properties do
    let definition ← IO.ofExcept (← PropertyDefinition.readRecord property.metadataPath)
    let some id := definition.id? | throw (IO.userError "property metadata has no ID")
    descriptions := descriptions.push (Json.mkObj [
      ("id", .str id), ("models", toJson property.run.models)])
    for model in property.run.models do
      unless models.contains model do models := models.push model
  IO.println (Json.mkObj [
    ("properties", .arr descriptions), ("models", toJson models),
    ("legacy_models", toJson legacyModels)]).compress
  return 0

end Workflow.Declarative.Discovery

import Workflow.Declarative.Generator

namespace Workflow.Declarative

open Lean

structure LoadedProperty where
  property : Property
  definition : PropertyDefinition
  id : String
  version : Int

/-- This catalogue is assembled from discovered declarations, with no candidate cases. -/
structure Catalogue where
  properties : Array LoadedProperty
  models : Array Model

def Catalogue.checks (catalogue : Catalogue) : Array CheckId :=
  catalogue.properties.flatMap fun property =>
    property.property.run.modelIds.map fun modelId =>
      { propertyId := property.id, definitionVersion := property.version, modelId }

def Catalogue.loadCheck (catalogue : Catalogue) (id : CheckId) :
    Except String Generator.ConfiguredCheck := do
  let [loaded] := (catalogue.properties.filter fun p =>
    p.id == id.propertyId && p.version == id.definitionVersion).toList
    | throw "unknown or ambiguous property/version"
  let [selected] := (loaded.property.run.models.filter (·.id == id.modelId)).toList
    | throw "model is not enabled or is ambiguous in this property's Run.lean"
  let [model] := (catalogue.models.filter (·.runnable.metadata.id == id.modelId)).toList
    | throw "unknown or ambiguous transaction model"
  let metadata ← TransactionModel.parse model.runnable.metadata.toJson
  let combinedCheck ← CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str loaded.id), ("definition_version", toJson loaded.version)]),
    ("tx_model", .str id.modelId),
    ("limitations", toJson selected.limitations)])
  let binding : CheckBinding := { combinedCheck, txModel := metadata }
  binding.validate loaded.id loaded.definition
  return {
    context := { propertyDefinition := loaded.definition, binding }
    generate := generate loaded.id loaded.property model }

/-- Read existing property metadata and reject inconsistent discovery before any proofs. -/
def Catalogue.load (properties : Array Property) (models : Array Model) :
    IO (Except String Catalogue) := do
  let mut loaded : Array LoadedProperty := #[]
  for property in properties do
    let definition ← match ← PropertyDefinition.readRecord property.metadataPath with
      | .ok definition => pure definition
      | .error message => return .error message
    let some id := definition.id? | return .error "property metadata is missing its ID"
    let some version := definition.version? | return .error "property metadata is missing its version"
    if let some primary := definition.primary? then
      unless primary == property.run.statement.definition.toString do
        return .error "Run.lean and metadata name different primary statements"
    if loaded.any (fun p => p.id == id && p.version == version) then
      return .error "duplicate property/version in discovery"
    unless property.run.modelIds.toList.eraseDups.length == property.run.models.size do
      return .error "duplicate allowed model in Run.lean"
    loaded := loaded.push { property, definition, id, version }
  let ids := models.map (·.runnable.metadata.id)
  unless ids.toList.eraseDups.length == ids.size do
    return .error "duplicate transaction-model ID in discovery"
  let catalogue : Catalogue := { properties := loaded, models }
  for check in catalogue.checks do
    if let .error message := catalogue.loadCheck check then return .error message
  return .ok catalogue

end Workflow.Declarative

import Workflow.Metadata.Property

namespace Workflow

open Lean

namespace ModelMetadata

private def field (value : Json) (name : String) : Option Json :=
  (value.getObjVal? name).toOption

private def object (value : Json) (path : String) (known : Array String) : Except String Unit := do
  let fields ← value.getObj?.mapError fun _ => s!"{path}: expected an object"
  fields.foldl (init := .ok ()) fun result name _ => do
    result
    unless known.contains name do throw s!"{path}.{name}: unknown field"

private def string (value : Json) (path : String) : Except String Unit := do
  let _ ← value.getStr?.mapError fun _ => s!"{path}: expected a string"
  return ()

private def integer? (value : Json) : Option Int :=
  match value with
  | .num number =>
    if number.mantissa == 0 then some 0
    else if number.exponent >= (toString number.mantissa.natAbs).length then none
    else
      let divisor : Int := 10 ^ number.exponent
      if number.mantissa % divisor == 0 then some (number.mantissa / divisor) else none
  | _ => none

private def integer (value : Json) (path : String) : Except String Unit := do
  unless (integer? value).isSome do throw s!"{path}: expected an integer"

private def stringList (value : Json) (path : String) : Except String Unit := do
  let items ← value.getArr?.mapError fun _ => s!"{path}: expected an array of strings"
  for index in [:items.size] do
    string items[index]! s!"{path}[{index}]"

private def optional (value : Json) (name path : String)
    (validate : Json → String → Except String Unit) : Except String Unit := do
  if let some item := field value name then validate item s!"{path}.{name}"

private def collection {α : Type} (parseAt : Json → String → Except String α)
    (kind : String) (value : Json) : Except String (Array α) := do
  let items ← value.getArr?.mapError fun _ => s!"$: expected an array of {kind}"
  let mut result := #[]
  for index in [:items.size] do
    result := result.push (← parseAt items[index]! s!"$[{index}]")
  return result

private def readRecords {α : Type} (parseList : Json → Except String (Array α))
    (path : System.FilePath) : IO (Except String (Array α)) := do
  try
    let source ← IO.FS.readFile path
    return do
      let value ← Json.parse source |>.mapError fun message => s!"{path}: invalid JSON: {message}"
      parseList value |>.mapError fun message => s!"{path}: {message}"
  catch error =>
    return .error s!"{path}: {error}"

private def textValue (value : Json) : String :=
  match value with
  | .str text => text
  | _ => value.compress

private def suppliedText (value : Json) (names : Array String) : Array (String × String) := Id.run do
  let mut result := #[]
  for name in names do
    if let some item := field value name then
      result := result.push (name, textValue item)
  return result

end ModelMetadata

open ModelMetadata

/-- Descriptive transaction-model metadata with the original supplied fields. -/
structure TransactionModel where
  value : Json
  deriving BEq

namespace TransactionModel

private def parseAt (value : Json) (path : String) : Except String TransactionModel := do
  let names := #["id", "title", "plutus_version", "description"]
  object value path names
  for name in names do optional value name path string
  return { value }

def parse (value : Json) : Except String TransactionModel := parseAt value "$"

def parseList (value : Json) : Except String (Array TransactionModel) :=
  collection parseAt "transaction models" value

def read (path : System.FilePath) : IO (Except String (Array TransactionModel)) :=
  readRecords parseList path

def toJson (model : TransactionModel) : Json := model.value

def id? (model : TransactionModel) : Option String := do
  (← field model.value "id").getStr?.toOption

def plutusVersion? (model : TransactionModel) : Option String := do
  (← field model.value "plutus_version").getStr?.toOption

def textFields (model : TransactionModel) : Array (String × String) :=
  suppliedText model.value #["id", "title", "plutus_version", "description"]

end TransactionModel

/-- A descriptive association between a property definition and a model. -/
structure CombinedCheck where
  value : Json
  deriving BEq

namespace CombinedCheck

private def property (value : Json) (path : String) : Except String Unit := do
  object value path #["id", "definition_version"]
  optional value "id" path string
  optional value "definition_version" path integer

private def parseAt (value : Json) (path : String) : Except String CombinedCheck := do
  object value path #["property", "tx_model", "limitations"]
  optional value "property" path property
  optional value "tx_model" path string
  optional value "limitations" path stringList
  return { value }

def parse (value : Json) : Except String CombinedCheck := parseAt value "$"

def parseList (value : Json) : Except String (Array CombinedCheck) :=
  collection parseAt "combined checks" value

def read (path : System.FilePath) : IO (Except String (Array CombinedCheck)) :=
  readRecords parseList path

def toJson (check : CombinedCheck) : Json := check.value

def propertyId? (check : CombinedCheck) : Option String := do
  let property ← field check.value "property"
  (← field property "id").getStr?.toOption

def definitionVersion? (check : CombinedCheck) : Option Int := do
  let property ← field check.value "property"
  integer? (← field property "definition_version")

def txModelId? (check : CombinedCheck) : Option String := do
  (← field check.value "tx_model").getStr?.toOption

def textFields (check : CombinedCheck) : Array (String × String) := Id.run do
  let mut result := #[]
  if let some property := field check.value "property" then
    let entries := suppliedText property #["id", "definition_version"]
    if entries.isEmpty then result := result.push ("property", property.compress)
    else result := result ++ entries.map (fun (name, value) => (s!"property.{name}", value))
  return result ++ suppliedText check.value #["tx_model", "limitations"]

end CombinedCheck

/-- The exact descriptive snapshots associated with one registered construction. -/
structure CheckBinding where
  combinedCheck : CombinedCheck
  txModel : TransactionModel
  deriving BEq

namespace CheckBinding

/-- Resolve runtime identity without making descriptive schema fields mandatory. -/
def validate (binding : CheckBinding) (propertyId : String)
    (definition : PropertyDefinition) : Except String Unit := do
  let some definitionId := definition.id?
    | throw "property definition has no ID for model binding"
  unless !definitionId.trim.isEmpty && propertyId == definitionId do
    throw "model binding property does not match the property definition"
  let some version := definition.version?
    | throw "property definition has no definition version for model binding"
  unless binding.combinedCheck.propertyId? == some propertyId &&
      binding.combinedCheck.definitionVersion? == some version do
    throw "combined check does not match the selected property ID and definition version"
  let some modelId := binding.txModel.id?
    | throw "transaction model has no ID for model binding"
  unless !modelId.trim.isEmpty && binding.combinedCheck.txModelId? == some modelId do
    throw "combined check does not match the selected transaction-model ID"

/-- Select one exact registered combination, rejecting missing or ambiguous records. -/
def resolve (definition : PropertyDefinition) (modelId : String)
    (models : Array TransactionModel) (checks : Array CombinedCheck) : Except String CheckBinding := do
  let some propertyId := definition.id?
    | throw "property definition has no ID for model binding"
  let some version := definition.version?
    | throw "property definition has no definition version for model binding"
  unless !propertyId.trim.isEmpty && !modelId.trim.isEmpty do
    throw "property and transaction-model IDs must be nonempty for model binding"
  let selectedModels := models.filter (fun model => model.id? == some modelId)
  let model ← match selectedModels.toList with
    | [model] => pure model
    | [] => throw s!"transaction model {modelId} is missing from the catalogue"
    | _ => throw s!"transaction model {modelId} occurs more than once in the catalogue"
  let selectedChecks := checks.filter fun check =>
    check.propertyId? == some propertyId && check.definitionVersion? == some version &&
      check.txModelId? == some modelId
  let combinedCheck ← match selectedChecks.toList with
    | [check] => pure check
    | [] => throw s!"combined check for {propertyId} version {version} and {modelId} is missing"
    | _ => throw s!"combined check for {propertyId} version {version} and {modelId} occurs more than once"
  let binding := { combinedCheck, txModel := model : CheckBinding }
  binding.validate propertyId definition
  return binding

end CheckBinding
end Workflow

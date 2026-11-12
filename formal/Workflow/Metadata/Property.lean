import Lean

namespace Workflow

open Lean

/-- Descriptive property metadata, preserved without resolving its references. -/
structure PropertyDefinition where
  value : Json
  deriving BEq

namespace PropertyDefinition

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

private def strings (value : Json) (path : String) (names : Array String) : Except String Unit := do
  for name in names do optional value name path string

private def identity (value : Json) (path : String) : Except String Unit := do
  object value path #["id", "definition_version", "title", "category"]
  strings value path #["id", "title", "category"]
  optional value "definition_version" path integer

private def explanation (value : Json) (path : String) : Except String Unit := do
  object value path #["summary", "claim", "purpose"]
  strings value path #["summary", "claim", "purpose"]

private def scope (value : Json) (path : String) : Except String Unit := do
  let names := #["relevance_conditions", "preconditions", "limitations"]
  object value path names
  for name in names do optional value name path stringList

private def formalization (value : Json) (path : String) : Except String Unit := do
  object value path #["primary", "theorems"]
  optional value "primary" path string
  optional value "theorems" path stringList

private def references (value : Json) (path : String) : Except String Unit := do
  let items ← value.getArr?.mapError fun _ => s!"{path}: expected an array of references"
  for index in [:items.size] do
    let item := items[index]!
    let itemPath := s!"{path}[{index}]"
    object item itemPath #["label", "target"]
    strings item itemPath #["label", "target"]

private def parseAt (value : Json) (path : String) : Except String PropertyDefinition := do
  object value path #["schema_version", "identity", "explanation", "scope", "formalization", "references"]
  optional value "schema_version" path integer
  optional value "identity" path identity
  optional value "explanation" path explanation
  optional value "scope" path scope
  optional value "formalization" path formalization
  optional value "references" path references
  return { value }

/-- Validate the fixed metadata layout without requiring any field to be present. -/
def parse (value : Json) : Except String PropertyDefinition := parseAt value "$"

def parseList (value : Json) : Except String (Array PropertyDefinition) := do
  let items ← value.getArr?.mapError fun _ => "$: expected an array of property definitions"
  let mut result := #[]
  for index in [:items.size] do
    result := result.push (← parseAt items[index]! s!"$[{index}]")
  return result

private def readAs {A : Type} (parseDocument : Json → Except String A)
    (path : System.FilePath) : IO (Except String A) := do
  try
    let source ← IO.FS.readFile path
    return do
      let value ← Json.parse source |>.mapError fun message => s!"{path}: invalid JSON: {message}"
      parseDocument value |>.mapError fun message => s!"{path}: {message}"
  catch error =>
    return .error s!"{path}: {error}"

/-- Compatibility reader for a collection of property records. -/
def read (path : System.FilePath) : IO (Except String (Array PropertyDefinition)) :=
  readAs parseList path

/-- Read the single metadata record maintained in one property folder. -/
def readRecord (path : System.FilePath) : IO (Except String PropertyDefinition) :=
  readAs parse path

def toJson (definition : PropertyDefinition) : Json := definition.value

def id? (definition : PropertyDefinition) : Option String := do
  let identity ← field definition.value "identity"
  let value ← field identity "id"
  value.getStr?.toOption

def version? (definition : PropertyDefinition) : Option Int := do
  let identity ← field definition.value "identity"
  integer? (← field identity "definition_version")

def primary? (definition : PropertyDefinition) : Option String := do
  let formalization ← field definition.value "formalization"
  let value ← field formalization "primary"
  value.getStr?.toOption

private def textValue (value : Json) : String :=
  match value with
  | .str text => text
  | _ => value.compress

private def groupText (value : Json) (name : String) (keys : Array String) : Array (String × String) := Id.run do
  let some group := field value name | return #[]
  let mut result := #[]
  for key in keys do
    if let some item := field group key then
      result := result.push (s!"{name}.{key}", textValue item)
  if result.isEmpty then return #[(name, group.compress)]
  return result

/-- Supplied fields for plain-text reports; callers escape text for their output format. -/
def textFields (definition : PropertyDefinition) : Array (String × String) := Id.run do
  let value := definition.value
  let mut result := #[]
  if let some version := field value "schema_version" then
    result := result.push ("schema_version", textValue version)
  result := result ++ groupText value "identity" #["id", "definition_version", "title", "category"]
  result := result ++ groupText value "explanation" #["summary", "claim", "purpose"]
  result := result ++ groupText value "scope" #["relevance_conditions", "preconditions", "limitations"]
  result := result ++ groupText value "formalization" #["primary", "theorems"]
  if let some references := field value "references" then
    if let .ok items := references.getArr? then
      if items.isEmpty then result := result.push ("references", "[]")
      for index in [:items.size] do
        result := result ++ groupText
          (Json.mkObj [(s!"references[{index}]", items[index]!)])
          s!"references[{index}]" #["label", "target"]
  return result

end PropertyDefinition
end Workflow

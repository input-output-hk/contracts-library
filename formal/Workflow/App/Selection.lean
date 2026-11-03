import Workflow.Types.Check

namespace Workflow.App

open Lean

structure Request where
  path : System.FilePath
  validators : Array String := #[]
  properties : Array String := #[]
  checksFile : Option System.FilePath := none
  timeoutMs : Nat := 300000
  args : Array String := #[]

private def value (option argument : String) : Except String String := do
  if argument.trim.isEmpty || argument.startsWith "--" then
    throw s!"{option} requires a value"
  return argument

private def parseOptions : List String → Request → Bool → Except String Request
  | [], request, _ => do
    if !request.properties.isEmpty && request.checksFile.isSome then
      throw "--check and --checks-file cannot be combined"
    return request
  | "--validator" :: name :: rest, request, timeoutSeen => do
    let name ← value "--validator" name
    parseOptions rest { request with validators := request.validators.push name } timeoutSeen
  | "--check" :: id :: rest, request, timeoutSeen => do
    let id ← value "--check" id
    parseOptions rest { request with properties := request.properties.push id } timeoutSeen
  | "--checks-file" :: path :: rest, request, timeoutSeen => do
    if request.checksFile.isSome then throw "--checks-file may be supplied only once"
    let path ← value "--checks-file" path
    parseOptions rest { request with checksFile := some path } timeoutSeen
  | "--timeout-ms" :: argument :: rest, request, timeoutSeen => do
    if timeoutSeen then throw "--timeout-ms may be supplied only once"
    let some timeoutMs := argument.toNat?
      | throw "--timeout-ms requires positive milliseconds"
    if timeoutMs == 0 then throw "--timeout-ms requires positive milliseconds"
    parseOptions rest { request with timeoutMs } true
  | option :: _, _, _ => .error s!"unexpected or incomplete argument: {option}"

/-- Parse selection controls while retaining the original invocation. -/
def parseRequest (args : List String) : Except String Request := do
  let initial : Request := { path := "plutus.json", args := args.toArray }
  let path :: rest := args | return initial
  if path.startsWith "--" then return ← parseOptions args initial false
  let path ← value "blueprint" path
  let initial := { initial with path }
  match rest with
  | selector :: options =>
    if selector.startsWith "--" then parseOptions rest initial false
    else
      let selector ← value "validator" selector
      parseOptions options { initial with validators := #[selector] } false
  | [] => return initial

private def unique [BEq α] (values : Array α) : Array α :=
  values.foldl (fun result item => if result.contains item then result else result.push item) #[]

/-- Resolve selectors to canonical names in blueprint order. -/
def selectValidators (selectors names : Array String) : Except String (Array String) := do
  let names := unique names
  if selectors.isEmpty then return names
  let mut selected := #[]
  for selector in selectors do
    let candidates := names.filter fun name =>
      name == selector || (name.splitOn ".").getLast! == selector
    if candidates.isEmpty then throw s!"no validator matches '{selector}'"
    if candidates.size != 1 then
      throw s!"ambiguous validator '{selector}': {String.intercalate ", " candidates.toList}"
    selected := selected.push candidates[0]!
  return names.filter selected.contains

private def selectedProperties (request : Request) (known : Array String)
    (fileSource : Option String) : Except String (Array String) := do
  if request.checksFile.isSome then
    unless request.properties.isEmpty do throw "--check and --checks-file cannot be combined"
    let some source := fileSource | throw "selection file contents are missing"
    let json ← Json.parse source |>.mapError fun message => s!"invalid selection JSON: {message}"
    let fields ← json.getObj?.mapError fun _ => "selection file must be an object of property IDs and booleans"
    fields.foldl (init := .ok #[]) fun result id enabled => do
      let selected ← result
      unless known.contains id do throw s!"unknown property in selection file: {id}"
      let enabled ← enabled.getBool?.mapError fun _ => s!"{id}: selection must be true or false"
      return if enabled then selected.push id else selected
  else
    if fileSource.isSome then throw "selection contents were supplied without --checks-file"
    for id in request.properties do
      unless known.contains id do throw s!"unknown property: {id}"
    return if request.properties.isEmpty then known else request.properties

/-- Select only registered pairings, preserving registry order and exact versions. -/
def selectChecks (request : Request) (registry : Array CheckId)
    (fileSource : Option String) : Except String (Array CheckId) := do
  let registry := unique registry
  let selected ← selectedProperties request (unique (registry.map (·.propertyId))) fileSource
  return registry.filter fun check => selected.contains check.propertyId

end Workflow.App

import Workflow.Declarative.Types
import Workflow.App.Selection

namespace Workflow.Declarative.Discovery

open Lean System

structure Entry where
  id : String
  path : FilePath
  deriving Inhabited, Repr

structure PropertySource where
  runModule : String
  runDeclaration : String
  definitionModule : String
  metadataPath : FilePath
  runPath : FilePath
  deriving Inhabited, Repr

structure ModelSource where
  moduleName : String
  exportName : String
  path : FilePath
  deriving Inhabited, Repr

private def component (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
    ('A' ≤ first && first ≤ 'Z') &&
      rest.all (fun c => c.isAlphanum && c.toNat < 128 || c == '_')

/-- Module identities come from validated paths relative to the source checkout. -/
def moduleName (path : FilePath) : Except String String := do
  unless path.extension == some "lean" do throw s!"invalid Lean module path: {path}"
  let parts := (path.withExtension "").components
  unless !path.isAbsolute && !parts.isEmpty && parts.all component do
    throw s!"invalid Lean module path: {path}"
  return String.intercalate "." parts

private partial def runFiles (root relative : FilePath) : IO (Array FilePath) := do
  let mut found := #[]
  let entries ← (root / relative).readDir
  for entry in entries.qsort (fun a b => a.fileName < b.fileName) do
    let path := relative / entry.fileName
    match (← (root / path).symlinkMetadata).type with
    | .dir => found := found ++ (← runFiles root path)
    | .file => if entry.fileName == "Run.lean" then found := found.push path
    | _ => pure ()
  return found

/-- Inspect identities without importing property or model implementations. -/
def scan (root : FilePath) : IO (Array Entry × Array String) := do
  let directory := root / "Formal/Properties"
  if !(← directory.pathExists) then return (#[], #[])
  let mut entries := #[]
  let mut errors := #[]
  for path in ← runFiles root "Formal/Properties" do
    let metadata := path.withFileName "metadata.json"
    try
      let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / metadata)))
      let id ← IO.ofExcept do (← json.getObjVal? "identity").getObjValAs? String "id"
      unless !id.trim.isEmpty do throw (IO.userError "missing property ID")
      entries := entries.push { id, path }
    catch error => errors := errors.push s!"{metadata}: {error}"
  return (entries, errors)

/-- Use the app's selection contract, then preserve discovery order. -/
def select (request : Workflow.App.Request) (known : Array String)
    (source : Option String) : Except String (Array String) := do
  let chosen ← Workflow.App.selectedProperties request known source
  return known.filter chosen.contains

/-- Validate only selected properties, leaving unrelated incomplete sources alone. -/
def propertiesFor (root : FilePath) (entries : Array Entry) (selected : Array String) :
    IO (Array PropertySource) := do
  let mut properties := #[]
  let mut identities := #[]
  for entry in entries do
    if !selected.contains entry.id then continue
    if identities.contains entry.id then throw (IO.userError s!"duplicate property ID: {entry.id}")
    identities := identities.push entry.id
    let definition := entry.path.withFileName "Definition.lean"
    unless ← (root / definition).pathExists do
      throw (IO.userError s!"{entry.path}: requires Definition.lean")
    let runModule ← IO.ofExcept (moduleName entry.path)
    let definitionModule ← IO.ofExcept (moduleName definition)
    let namespaceName := String.intercalate "." (runModule.splitOn "." |>.dropLast)
    properties := properties.push {
      runModule, runDeclaration := namespaceName ++ ".run", definitionModule
      metadataPath := entry.path.withFileName "metadata.json", runPath := entry.path }
  return properties

/-- The expected native export is type-checked by the generated bootstrap. -/
def modelsFor (root : FilePath) (ids : Array String) : IO (Array ModelSource) := do
  let mut models := #[]
  let mut seen := #[]
  for id in ids do
    if seen.contains id then continue
    seen := seen.push id
    let digits := id.drop 4
    unless id.startsWith "TxM-" && !digits.isEmpty && digits.toList.all Char.isDigit do
      throw (IO.userError s!"invalid model ID: {id}")
    let stem := "TxM" ++ digits
    let path : FilePath := "Formal/TxModels/Definitions" / (stem ++ ".lean")
    unless ← (root / path).pathExists do throw (IO.userError s!"unknown model: {id}")
    models := models.push {
      moduleName := ← IO.ofExcept (moduleName path)
      exportName := s!"Formal.TxModels.{stem}.runnable", path }
  return models

private def propertyEntries (properties : Array PropertySource) : String :=
  "#[" ++ String.intercalate ",\n      " (properties.toList.map fun p =>
    "{ run := " ++ p.runDeclaration ++ ", runModule := " ++ reprStr p.runModule ++
    ", definitionModule := " ++ reprStr p.definitionModule ++ ", metadataPath := " ++
    reprStr p.metadataPath.toString ++ " }") ++ "]"

private def unique (items : Array String) : Array String :=
  items.foldl (fun result item => if result.contains item then result else result.push item) #[]

def propertyModules (properties : Array PropertySource) : Array String :=
  unique (properties.map (·.runModule))

def modelModules (properties : Array PropertySource) (models : Array ModelSource) : Array String :=
  unique (propertyModules properties ++ models.map (·.moduleName))

/-- Evaluate actual run declarations before importing their selected models. -/
def planSource (properties : Array PropertySource) : String :=
  String.intercalate "\n" ((#["Workflow.Declarative.Discovery"] ++ propertyModules properties).toList.map
    (fun name => "import " ++ name)) ++
    "\n\ndef main : IO UInt32 :=\n  Workflow.Declarative.Discovery.describe\n    " ++
    propertyEntries properties ++ "\n"

def bootstrap (properties : Array PropertySource) (models : Array ModelSource)
    (known : Array String := #[]) (snapshot index startedMarker : Option FilePath := none) : String :=
  let optional := fun path : Option FilePath =>
    path.map (fun p => "(some " ++ reprStr p.toString ++ ")") |>.getD "none"
  let modelEntries := "#[" ++ String.intercalate ",\n      " (models.toList.map fun m =>
    "{ moduleName := " ++ reprStr m.moduleName ++ ", runnable := " ++ m.exportName ++ " }") ++ "]"
  let start := match startedMarker with
    | none => ""
    | some path =>
      "  let startedAt ← IO.monoMsNow\n" ++
      "  IO.FS.writeFile " ++ reprStr (path.withExtension "tmp").toString ++ " (toString startedAt)\n" ++
      "  IO.FS.rename " ++ reprStr (path.withExtension "tmp").toString ++ " " ++ reprStr path.toString ++ "\n"
  String.intercalate "\n" ((#["Workflow.Declarative.CLI"] ++ modelModules properties models).toList.map
    (fun name => "import " ++ name)) ++
    "\n\ndef main (args : List String) : IO UInt32 := do\n" ++ start ++
    "  Workflow.Declarative.main\n    " ++
    propertyEntries properties ++ "\n    " ++ modelEntries ++ " args\n    #[" ++
    String.intercalate ", " (known.toList.map reprStr) ++ "]\n    " ++
    optional snapshot ++ "\n    " ++ optional index ++ "\n"

/-- Evaluate actual Run.lean declarations before importing model implementations. -/
def describe (properties : Array Property) : IO UInt32 := do
  let mut descriptions : Array Json := #[]
  let mut models : Array String := #[]
  for property in properties do
    let definition ← IO.ofExcept (← PropertyDefinition.readRecord property.metadataPath)
    let some id := definition.id? | throw (IO.userError "property metadata has no ID")
    descriptions := descriptions.push (Json.mkObj [
      ("id", .str id), ("models", toJson property.run.modelIds)])
    for model in property.run.modelIds do
      unless models.contains model do models := models.push model
  IO.println (Json.mkObj [
    ("properties", .arr descriptions), ("models", toJson models)]).compress
  return 0

end Workflow.Declarative.Discovery

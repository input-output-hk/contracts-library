import Lean.Elab.Import
import Workflow.Types.Jobs

namespace Workflow.App.Sources

open Lean System

structure Options where
  projectRoot : FilePath
  leanPath : String
  leanCommand : String := "lean"
  timeoutCommand : String := "timeout"
  budgetMs : Nat := 30000

private structure Entry where
  moduleName : String
  imports : Array String
  sha256 : String
  state : String := "captured"
  compiledSha256 : Option String := none
  error : Option String := none

private structure State where
  entries : Array Entry := #[]
  externalImports : Array String := #[]
  error : Option String := none

structure Session where
  private options : Options
  private directory : FilePath
  private identities : Json
  private state : IO.Ref State

private def relativeSource (name : String) : FilePath :=
  FilePath.mk (name.replace "." "/" ++ ".lean")

private def relativeCompiled (name : String) : FilePath :=
  FilePath.mk (name.replace "." "/" ++ ".olean")

private def entryJson (entry : Entry) : Json := Json.mkObj [
  ("module", .str entry.moduleName),
  ("source", .str ("sources/" ++ (relativeSource entry.moduleName).toString)),
  ("sha256", .str entry.sha256), ("imports", toJson entry.imports),
  ("state", .str entry.state), ("compiled_sha256", toJson entry.compiledSha256),
  ("compiled", entry.compiledSha256.map (fun _ =>
    Json.str ("sources/" ++ (relativeCompiled entry.moduleName).toString)) |>.getD .null),
  ("error", toJson entry.error)]

private def writeText (path : FilePath) (contents : String) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .write
  handle.putStr contents
  handle.flush

private def save (session : Session) : IO Unit := do
  let state ← session.state.get
  writeText (session.directory / "index.json.tmp") (Json.mkObj [
    ("schema_version", toJson (1 : Nat)),
    ("purpose", .str "Project sources compiled for this run; external libraries use the prepared environment."),
    ("environment", session.identities), ("sources", .arr (state.entries.map entryJson)),
    ("external_imports", toJson state.externalImports), ("error", toJson state.error)]).pretty
  IO.FS.rename (session.directory / "index.json.tmp") (session.directory / "index.json")

private def output (command : String) (args : Array String) (cwd : FilePath) : IO String := do
  let result ← IO.Process.output { cmd := command, args, cwd := some cwd }
  unless result.exitCode == 0 do
    throw (IO.userError s!"{command} failed: {result.stderr}")
  return result.stdout.trim

private def hash (path : FilePath) : IO String := do
  let value ← output "sha256sum" #[path.toString] (← IO.currentDir)
  let digest := (value.splitOn " ").head!
  unless digest.length == 64 do throw (IO.userError s!"invalid SHA-256 output for {path}")
  return digest

private def gitIdentity (directory : FilePath) : IO Json := do
  try
    let revision ← output "git" #["rev-parse", "HEAD"] directory
    let trackedStatus ← output "git" #["status", "--porcelain", "--untracked-files=no"] directory
    return Json.mkObj [("revision", .str revision), ("tracked_dirty", toJson (!trackedStatus.isEmpty)),
      ("tracked_status", .str trackedStatus)]
  catch error =>
    return Json.mkObj [("error", .str error.toString)]

/-- Start one run's source record without changing the project or its dependencies. -/
def create (runDirectory : FilePath) (options : Options) : IO Session := do
  let directory := runDirectory / "sources"
  if ← directory.pathExists then
    throw (IO.userError s!"source bundle already exists: {directory}")
  IO.FS.createDirAll directory
  let directory ← IO.FS.realPath directory
  let projectRoot ← IO.FS.realPath options.projectRoot
  let paths := options.leanPath.splitOn ":" |>.map fun path =>
    let path := FilePath.mk path
    (if path.isAbsolute then path else projectRoot / path).toString
  let options := { options with projectRoot, leanPath := String.intercalate ":" paths }
  let state ← IO.mkRef ({} : State)
  let mut session : Session := { options, directory, identities := .null, state }
  try
    let version ← try
      pure (Json.mkObj [("output", .str (← output options.timeoutCommand
        #["--signal=KILL", "5s", options.leanCommand, "--version"] options.projectRoot))])
      catch error => pure (Json.mkObj [("error", .str error.toString)])
    let mut pins : Array Json := #[]
    let mut dependencies : Array Json := #[]
    for name in #["lean-toolchain", "lake-manifest.json", "lakefile.toml", "lakefile.lean"] do
      let path := options.projectRoot / name
      if ← path.pathExists then
        let content ← IO.FS.readFile path
        writeText (directory / name) content
        pins := pins.push (Json.mkObj [("path", .str ("sources/" ++ name)),
          ("sha256", .str (← hash (directory / name)))])
        if name == "lake-manifest.json" then
          let manifest ← IO.ofExcept (Json.parse content)
          let packages ← IO.ofExcept ((← IO.ofExcept (manifest.getObjVal? "packages")).getArr?)
          let packageDirectory := (manifest.getObjValAs? String "packagesDir").toOption.getD ".lake/packages"
          for package in packages do
            let packageName ← IO.ofExcept (package.getObjValAs? String "name")
            let actual ← gitIdentity (options.projectRoot / packageDirectory / packageName)
            dependencies := dependencies.push (Json.mkObj [("pinned", package), ("actual", actual)])
    session := { session with identities := Json.mkObj [
      ("lean_version", version), ("lean_command", .str options.leanCommand),
      ("prepared_lean_path", .str options.leanPath),
      ("project", ← gitIdentity options.projectRoot),
      ("pins", .arr pins), ("dependencies", .arr dependencies)] }
    save session
    return session
  catch error =>
    state.modify fun value => { value with error := some error.toString }
    save session
    throw error

private def imports (source file : String) : IO (Array String) := do
  let (header, _, messages) ← Lean.Parser.parseHeader (Lean.Parser.mkInputContext source file)
  if messages.hasErrors then
    throw (IO.userError s!"cannot parse Lean import header: {file}")
  return (Lean.Elab.headerToImports header).map (fun item => item.module.toString)

private def isProject (session : Session) (name : String) : IO Bool := do
  let path := session.options.projectRoot / relativeSource name
  if ← path.pathExists then return true
  -- A missing module under a project source root is an error, not an external library.
  let root := (name.splitOn ".").head!
  return (← (session.options.projectRoot / root).isDir)

private partial def capture (session : Session) (generated : Array String)
    (visiting : Array String) (name : String) : IO Unit := do
  unless Workflow.validModuleName name do
    throw (IO.userError s!"unsafe or unsupported project import name: {name}")
  if generated.contains name then return
  if visiting.contains name then throw (IO.userError s!"cyclic project imports: {name}")
  if (← session.state.get).entries.any (·.moduleName == name) then return
  unless ← isProject session name do
    session.state.modify fun state =>
      if state.externalImports.contains name then state
      else { state with externalImports := state.externalImports.push name }
    return
  let original := session.options.projectRoot / relativeSource name
  let source ← IO.FS.readFile original
  let dependencies ← imports source original.toString
  let destination := session.directory / relativeSource name
  if ← destination.pathExists then throw (IO.userError s!"source snapshot already exists: {destination}")
  IO.FS.createDirAll destination.parent.get!
  writeText destination source
  let digest ← hash destination
  session.state.modify fun state => { state with entries := state.entries.push {
    moduleName := name, imports := dependencies, sha256 := digest } }
  save session
  -- Dependencies precede their importers in the manifest and compilation order.
  for dependency in dependencies do
    if generated.contains dependency then
      throw (IO.userError s!"project source {name} imports generated module {dependency}")
    capture session generated (visiting.push name) dependency
  session.state.modify fun state =>
    let own := state.entries.filter (·.moduleName == name)
    { state with entries := state.entries.filter (·.moduleName != name) ++ own }
  save session

private def duration (milliseconds : Nat) : String :=
  s!"{milliseconds / 1000}.{String.mk (List.replicate (3 - (toString (milliseconds % 1000)).length) '0')}{milliseconds % 1000}s"

private def updateEntry (session : Session) (name : String) (f : Entry → Entry) : IO Unit :=
  session.state.modify fun state => { state with entries := state.entries.map (fun entry =>
    if entry.moduleName == name then f entry else entry) }

private def compile (session : Session) (leanPath : String) (deadline : Nat) (entry : Entry) : IO Unit := do
  if entry.state == "compiled" then
    let current ← hash (session.directory / relativeSource entry.moduleName)
    let compiled ← hash (session.directory / relativeCompiled entry.moduleName)
    unless current == entry.sha256 && some compiled == entry.compiledSha256 do
      throw (IO.userError s!"saved source or compiled module changed: {entry.moduleName}")
    return
  unless entry.state == "captured" do
    throw (IO.userError s!"source compilation previously failed: {entry.moduleName}")
  let now ← IO.monoMsNow
  if now ≥ deadline then throw (IO.userError "source preparation exceeded its time budget")
  unless (← hash (session.directory / relativeSource entry.moduleName)) == entry.sha256 do
    throw (IO.userError s!"saved source changed before compilation: {entry.moduleName}")
  let source := relativeSource entry.moduleName
  let compiled := relativeCompiled entry.moduleName
  let args := #["--signal=KILL", duration (deadline - now), session.options.leanCommand,
    "-o", compiled.toString, source.toString]
  let log := session.directory / "_logs" / FilePath.mk (entry.moduleName.replace "." "/")
  IO.FS.createDirAll log.parent.get!
  writeText (FilePath.mk (log.toString ++ ".command.json")) (Json.mkObj [
    ("command", .str session.options.timeoutCommand), ("args", toJson args),
    ("cwd", .str session.directory.toString),
    ("environment", Json.mkObj [("LEAN_PATH", .str leanPath)])]).pretty
  updateEntry session entry.moduleName fun value => { value with state := "compiling" }
  save session
  try
    let result ← IO.Process.output {
      cmd := session.options.timeoutCommand, args, cwd := some session.directory,
      env := #[("LEAN_PATH", some leanPath)], setsid := true }
    writeText (FilePath.mk (log.toString ++ ".stdout")) result.stdout
    writeText (FilePath.mk (log.toString ++ ".stderr")) result.stderr
    writeText (FilePath.mk (log.toString ++ ".result.json")) (Json.mkObj [
      ("exit_code", toJson result.exitCode.toNat), ("elapsed_ms", toJson ((← IO.monoMsNow) - now))]).pretty
    unless result.exitCode == 0 do
      throw (IO.userError s!"source compilation failed ({result.exitCode}): {entry.moduleName}; see sources/_logs")
    unless (← hash (session.directory / source)) == entry.sha256 do
      throw (IO.userError s!"source changed during compilation: {entry.moduleName}")
    let digest ← hash (session.directory / compiled)
    updateEntry session entry.moduleName fun value =>
      { value with state := "compiled", compiledSha256 := some digest }
    save session
  catch error =>
    updateEntry session entry.moduleName fun value =>
      { value with state := "failed", error := some error.toString }
    save session
    throw error

/-- Capture imports before execution and compile only the saved project sources. -/
def prepare (session : Session) (plan : GenerationPlan) : IO String := do
  try
    if let some error := (← session.state.get).error then throw (IO.userError error)
    let generated := plan.modules.map (·.name)
    for module in plan.modules do
      for dependency in ← imports module.source module.name do
        capture session generated #[] dependency
    let leanPath := s!"{session.directory}:{session.options.leanPath}"
    let deadline := (← IO.monoMsNow) + session.options.budgetMs
    for entry in (← session.state.get).entries do
      compile session leanPath deadline entry
    save session
    return leanPath
  catch error =>
    session.state.modify fun state => { state with error := some error.toString }
    save session
    throw error

end Workflow.App.Sources

import Workflow.App.Selection
import Workflow.App.Output
import Workflow.App.Verification
import Workflow.App.Sources
import Workflow.App.Review

namespace Workflow.App.Run

open Lean

structure Options where
  executorOptions : Executor.Options
  outputRoot : System.FilePath := "output"

abbrev safeName := Workflow.App.safeName

private def save (run : RunRecord) : IO Unit := do
  run.save
  Review.write run

private def createDirectory (root : System.FilePath) : IO System.FilePath := do
  IO.FS.createDirAll root
  let root ← IO.FS.realPath root
  let date ← IO.Process.output { cmd := "date", args := #["-u", "+%Y%m%dT%H%M%SZ"] }
  unless date.exitCode == 0 do throw (IO.userError "could not determine the run timestamp")
  let created ← IO.Process.output {
    cmd := "mktemp", args := #["-d", (root / s!"run.{date.stdout.trim}.XXXXXXXX").toString] }
  unless created.exitCode == 0 do
    throw (IO.userError s!"could not create the run output folder: {created.stderr.trim}")
  return System.FilePath.mk created.stdout.trim

private def optionsJson (request : Request) (cwd : System.FilePath) : Json := Json.mkObj [
  ("args", toJson request.args), ("cwd", .str cwd.toString),
  ("blueprint", .str request.path.toString), ("timeout_ms", toJson request.timeoutMs),
  ("source_preparation_timeout_ms", toJson (max request.timeoutMs 30000)),
  ("validator_selectors", toJson request.validators), ("property_selectors", toJson request.properties),
  ("selection_file", request.checksFile.map (fun path => Json.str path.toString) |>.getD .null)]

private def matchingCheck (id : CheckId) (check : Generator.ConfiguredCheck) : Except String Unit := do
  unless check.context.propertyDefinition.id? == some id.propertyId &&
      check.context.propertyDefinition.version? == some id.definitionVersion &&
      check.context.binding.txModel.id? == some id.modelId do
    throw "loaded check does not match the requested property/version/model"
  check.context.binding.validate id.propertyId check.context.propertyDefinition

private def loadOne (load : CheckId → IO (Except String Generator.ConfiguredCheck))
    (id : CheckId) : IO (Except String Generator.ConfiguredCheck) := do
  try
    let result ← load id
    return do
      let check ← result
      matchingCheck id check
      return check
  catch error => return .error s!"could not load check: {error}"

private def verify (options : Options) (request : Request) (run : RunRecord)
    (prepareImports : GenerationPlan → IO String)
    (name : String) (prepared : InputResult) (id : CheckId)
    (check : Generator.ConfiguredCheck) : IO CheckRun := do
  let relative := checkDirectory name id
  let directory := run.directory / relative
  try
    let engine : Verification.Engine := {
      options := { options.executorOptions with
        prepareImports := some prepareImports
        budgetMs := request.timeoutMs
        directory := some directory } }
    let result ← engine.verifyOne prepared check
    let file := directory / "check-result.json"
    let saved ← IO.ofExcept (Json.parse (← IO.FS.readFile file))
    unless saved == result.toJson do
      throw (IO.userError "saved check result differs from the returned assessment")
    let target ← IO.ofExcept (saved.getObjVal? "target")
    let preparedInput ← IO.ofExcept (target.getObjVal? "prepared_input")
    let mut problem := none
    if preparedInput != .str (directory / "input.json").toString then
      problem := some "the check's prepared input could not be retained"
    let manifestPath := directory / "execution.json"
    let hasGeneratedSource := result.evidence.any (fun path => path.toString.endsWith ".lean")
    if (← manifestPath.pathExists) || (← (directory / "Generated").pathExists) || hasGeneratedSource then
      try
        let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile manifestPath))
        let failures ← IO.ofExcept do (← manifest.getObjVal? "retention_errors").getArr?
        unless failures.isEmpty do
          problem := some "execution files could not be retained; inspect execution.json"
      catch error => problem := some s!"the execution manifest could not be retained: {error}"
    return { id, result := some result, resultFile := some (relative / "check-result.json"), error := problem }
  catch error =>
    return { id, error := some s!"could not retain a matching check result: {error}" }

/-- Run the selected work from one captured blueprint and checkpoint its file index. -/
def runWith (registry : Array CheckId)
    (load : CheckId → IO (Except String Generator.ConfiguredCheck))
    (request : Request) (options : Options) : IO RunRecord := do
  let started ← IO.monoMsNow
  let directory ← createDirectory options.outputRoot
  let mut run : RunRecord := { directory, options := optionsJson request (← IO.currentDir) }
  let sourceSession ← IO.mkRef (none : Option Sources.Session)
  let sourceCreationError ← IO.mkRef (none : Option String)
  let projectRoot ← IO.currentDir
  let prepareImports := fun plan => do
    if let some message ← sourceCreationError.get then throw (IO.userError message)
    let session ← match ← sourceSession.get with
      | some session => pure session
      | none => do
        try
          let session ← Sources.create directory {
            projectRoot, leanPath := options.executorOptions.leanPath
            leanCommand := options.executorOptions.leanCommand
            timeoutCommand := options.executorOptions.timeoutCommand
            budgetMs := max request.timeoutMs 30000 }
          sourceSession.set (some session)
          pure session
        catch error =>
          sourceCreationError.set (some error.toString)
          throw error
    Sources.prepare session plan
  try
    save run
    let source ← IO.FS.readFile request.path
    writeText (directory / "input.json") source
    run := { run with input := some "input.json" }
    save run
    let fileSource ← match request.checksFile with
      | none => pure none
      | some path => do
        let contents ← IO.FS.readFile path
        writeText (directory / "checks.json") contents
        run := { run with options := run.options.setObjVal! "selection_snapshot" (.str "checks.json") }
        pure (some contents)
    let selected ← IO.ofExcept (selectChecks request registry fileSource)
    if registry.isEmpty then throw (IO.userError "no check implementations are registered")
    let folders := selected.map checkFolder
    unless folders.toList.eraseDups.length == folders.size do
      throw (IO.userError "registered check identities have colliding output folder names")
    let names ← IO.ofExcept ((Input.discover source).mapError toString)
    if names.isEmpty then throw (IO.userError "the blueprint contains no validators")
    let names ← IO.ofExcept (selectValidators request.validators names)
    run := { run with validators := names.map fun name =>
      { name, checks := selected.map fun id => { id } } }
    save run
    let configured ← selected.mapM (loadOne load)
    for index in [:run.validators.size] do
      let validator := run.validators[index]!
      if selected.isEmpty then continue
      match Input.parse source validator.name with
      | .error error =>
        let updated := { validator with preparationError := some (toString error) }
        run := { run with validators := run.validators.set! index updated }
        save run
      | .ok value =>
        let prepared := { value with sourcePath := some request.path }
        for checkIndex in [:selected.size] do
          let id := selected[checkIndex]!
          let some loaded := configured[checkIndex]?
            | throw (IO.userError "configured check list is incomplete")
          let result ← match loaded with
            | .error message => pure { id, error := some message : CheckRun }
            | .ok check => verify options request run prepareImports validator.name prepared id check
          let current := run.validators[index]!
          let updated := { current with checks := current.checks.set! checkIndex result }
          run := { run with validators := run.validators.set! index updated }
          if ← (directory / "sources/index.json").pathExists then
            run := { run with sourceIndex := some "sources/index.json" }
          run := { run with elapsedMs := (← IO.monoMsNow) - started }
          save run
    run := { run with finished := true, elapsedMs := (← IO.monoMsNow) - started }
    save run
    return run
  catch error =>
    run := { run with
      finished := false
      errors := run.errors.push error.toString
      elapsedMs := (← IO.monoMsNow) - started }
    try save run catch _ => pure ()
    return run

def usage : String :=
  "plutus-upv run [BLUEPRINT] [VALIDATOR] [--validator NAME] [--check PROPERTY_ID | --checks-file FILE] [--timeout-ms MILLISECONDS]"

def run (registry : Array CheckId)
    (load : CheckId → IO (Except String Generator.ConfiguredCheck))
    (args : List String) : IO UInt32 := do
  match parseRequest args with
  | .error message => IO.eprintln s!"{message}\nUsage: {usage}"; return 2
  | .ok request =>
    try
      let record ← runWith registry load request {
        executorOptions := { leanPath := (← IO.getEnv "LEAN_PATH").getD "" } }
      IO.print record.text
      return record.exitCode
    catch error =>
      IO.eprintln s!"Plutus UPV could not retain the run: {error}"
      return 2

end Workflow.App.Run

import Workflow.Executor.Process
import Workflow.Executor.Diagnostics

namespace Workflow.Executor

open Lean

private def writeEvidence (path : System.FilePath) (contents : String) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .write
  handle.putStr contents
  handle.flush

private def validate (plan : GenerationPlan) (options : Options) : Except String Unit := do
  plan.validateBindings
  unless options.budgetMs > 0 && !options.leanPath.trim.isEmpty do
    throw "a positive budget and a prepared Lean search path are required"
  unless plan.jobs.isEmpty == (plan.status == .noObligations) do
    throw "generation status and job count disagree"
  let mut names : Array String := #[]
  for source in plan.modules do
    unless validModuleName source.name && !names.contains source.name do
      throw s!"invalid or duplicate module name: {source.name}"
    names := names.push source.name
  let mut jobs : Array (String × String) := #[]
  for job in plan.jobs do
    unless names.contains job.moduleName && !jobs.contains (job.moduleName, job.name) do
      throw s!"missing module or duplicate job: {job.moduleName}.{job.name}"
    jobs := jobs.push (job.moduleName, job.name)
    let some source := plan.modules.find? (·.name == job.moduleName)
      | throw s!"missing module: {job.moduleName}"
    unless ((Diagnostics.ranges source.source).filter (·.name == job.name)).size == 1 do
      throw s!"job must identify exactly one top-level theorem or definition: {job.name}"

private def runStateText : RunState → String
  | .completed => "completed"
  | .timedOut => "timedOut"
  | .error => "error"
  | .noObligations => "noObligations"

private def observedText : ObservedResult → String
  | .valid => "valid"
  | .falsified => "falsified"
  | .inconclusive => "inconclusive"

private def jobRefJson (reference : JobRef) : Json :=
  Json.mkObj [("module", .str reference.moduleName), ("name", .str reference.name)]

private def manifest (plan : GenerationPlan) (options : Options) (result : Result) : Json :=
  let modules := result.modules.map fun item => Json.mkObj [
    ("name", .str item.name), ("path", .str item.path.toString),
    ("exitCode", item.process.exitCode.map (fun code => toJson code.toNat) |>.getD .null),
    ("timedOut", .bool (item.process.state == .timedOut)),
    ("invocation", item.process.invocation.map (·.toJson) |>.getD .null),
    ("elapsedMs", toJson item.process.elapsedMs)]
  let jobs := result.jobs.map fun item =>
    let diagnostics := item.diagnostics.map fun diagnostic => Json.mkObj [
      ("file", .str diagnostic.fileName), ("line", toJson diagnostic.line),
      ("column", toJson diagnostic.column), ("severity", .str diagnostic.severity),
      ("message", .str diagnostic.message)]
    Json.mkObj [
      ("property", .str item.job.propertyId), ("name", .str item.job.name),
      ("module", .str item.job.moduleName), ("scope", .str item.job.scope),
      ("statement", .str item.job.statement),
      ("role", .str item.job.role.label),
      ("txModelId", item.job.txModelId.map Json.str |>.getD .null),
      ("transactionModel", item.job.binding.map (fun binding => binding.txModel.toJson) |>.getD .null),
      ("combinedCheck", item.job.binding.map (fun binding => binding.combinedCheck.toJson) |>.getD .null),
      ("applicability", item.job.applicability.map jobRefJson |>.getD .null),
      ("expected", .str (if item.job.expected == .valid then "valid" else "falsified")),
      ("observed", .str (observedText item.observed)), ("evidenceComplete", .bool item.evidenceComplete),
      ("issues", toJson item.issues),
      ("diagnostics", .arr diagnostics)]
  Json.mkObj [
    ("target", .str plan.targetName), ("state", .str (runStateText result.state)),
    ("propertyDefinition", result.propertyDefinition.map (·.toJson) |>.getD .null),
    ("budgetMs", toJson options.budgetMs), ("elapsedMs", toJson result.elapsedMs),
    ("leanCommand", .str options.leanCommand), ("leanPath", .str (result.leanPath.getD options.leanPath)),
    ("timeoutCommand", .str options.timeoutCommand), ("problems", toJson result.problems),
    ("retention_errors", toJson result.retentionErrors),
    ("notes", toJson plan.notes), ("modules", .arr modules), ("jobs", .arr jobs)]

/-- Allocate a fresh private directory, optionally beneath a caller-selected output root. -/
def createRunDirectory (outputRoot : Option System.FilePath := none) : IO System.FilePath := do
  match outputRoot with
  | none => IO.FS.createTempDir
  | some root =>
    IO.FS.createDirAll root
    let root ← IO.FS.realPath root
    let result ← IO.Process.output {
      cmd := "mktemp", args := #["-d", (root / "run.XXXXXXXX").toString] }
    unless result.exitCode == 0 do
      throw (IO.userError s!"could not create output directory: {result.stderr.trim}")
    return System.FilePath.mk result.stdout.trim

private def execute (plan : GenerationPlan) (options : Options) (directory : System.FilePath)
    (started : Nat) : IO Result := do
  for source in plan.modules do
    let path := directory / (source.name.replace "." "/" ++ ".lean")
    IO.FS.createDirAll (path.parent.getD directory)
    writeEvidence path source.source
  let configuration ← try
    let leanPath ← match options.prepareImports with
      | none => pure options.leanPath
      | some prepare => prepare plan
    pure (.ok { options with leanPath } : Except String Executor.Options)
    catch error => pure (.error s!"could not prepare supporting sources: {error}")
  let options ← match configuration with
    | .ok options => pure options
    | .error message => return {
        state := .error, directory := some directory, propertyDefinition := plan.propertyDefinition
        problems := #[message], retentionErrors := #[message]
        elapsedMs := (← IO.monoMsNow) - started
        jobs := plan.jobs.map fun job => { job, issues := #[message] } }
  let started ← if options.prepareImports.isSome then IO.monoMsNow else pure started
  let deadline := started + options.budgetMs
  let mut result : Result := {
    state := .completed, directory := some directory
    leanPath := some options.leanPath
    propertyDefinition := plan.propertyDefinition }
  let mut stopped := false
  for source in plan.modules do
    unless stopped do
      let path := directory / (source.name.replace "." "/" ++ ".lean")
      let process ← Process.run options deadline
        #["--json", s!"--root={directory}", "-o", (path.withExtension "olean").toString, path.toString]
        #[("LEAN_PATH", some s!"{directory}:{options.leanPath}")]
      result := { result with modules := result.modules.push { name := source.name, path, process } }
      try
        writeEvidence (path.withExtension "stdout.log") process.stdout
        writeEvidence (path.withExtension "stderr.log") process.stderr
        let jobs := plan.jobs.filter (·.moduleName == source.name)
        let (observations, problems) := Diagnostics.observe source path jobs process
        let jobIssues := observations.foldl (fun acc row =>
          acc ++ row.issues.map (fun issue => s!"{row.job.name}: {issue}")) #[]
        result := { result with
          jobs := result.jobs ++ observations
          problems := result.problems ++ problems ++ jobIssues }
        if process.state == .timedOut then
          result := { result with state := .timedOut }
          stopped := true
        else if !problems.isEmpty || !jobIssues.isEmpty then
          result := { result with state := .error }
          stopped := true
      catch error =>
        let message := s!"could not retain module evidence: {error}"
        result := { result with state := .error }
        result := { result with
          problems := result.problems.push message
          retentionErrors := result.retentionErrors.push message }
        stopped := true
  for job in plan.jobs do
    unless result.jobs.any (fun item => item.job.moduleName == job.moduleName && item.job.name == job.name) do
      let issue := if result.modules.any (·.name == job.moduleName) then
        "module evidence could not be retained"
        else "job was not run because an earlier step did not complete"
      result := { result with jobs := result.jobs.push {
        job, issues := #[issue] } }
  let elapsed := (← IO.monoMsNow) - started
  if elapsed ≥ options.budgetMs then result := { result with state := .timedOut }
  return { result with elapsedMs := elapsed }

/-- Execute in a fresh directory and retain its sources, raw logs, and observations.
    No expectation comparison or waiver handling occurs here. -/
def run (plan : GenerationPlan) (options : Options) : IO (Except String Result) := do
  let started ← IO.monoMsNow
  match validate plan options with
  | .error message => return .error message
  | .ok _ => pure ()
  if plan.jobs.isEmpty then return .ok { state := .noObligations, propertyDefinition := plan.propertyDefinition }
  try
    let directory ← match options.directory with
      | none => createRunDirectory options.outputRoot
      | some path => do
        unless (← path.readDir).isEmpty do
          throw (IO.userError "the configured execution workspace must be empty")
        IO.FS.realPath path
    let result ← try execute plan options directory started catch error =>
      pure { state := .error, directory := some directory, propertyDefinition := plan.propertyDefinition,
             problems := #[error.toString], retentionErrors := #[error.toString], jobs := plan.jobs.map fun job =>
               { job, issues := #["executor file or process failure"] } }
    writeEvidence (directory / "execution.json") ((manifest plan options result).pretty ++ "\n")
    return .ok result
  catch error =>
    return .error s!"cannot retain executor evidence: {error}"

end Workflow.Executor

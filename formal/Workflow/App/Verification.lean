import Workflow.Input
import Workflow.Generator.Single
import Workflow.Executor
import Workflow.Assessor

namespace Workflow.Verification

/-- One captured read, preserving readable input even if validation fails. -/
structure Preparation where
  source : Option String
  result : Except Input.Error InputResult

def prepare (path : System.FilePath) (selector : String) : IO Preparation := do
  let (source, result) ← Input.readWithSource path selector
  return { source, result }

/-- Operational settings are configured once, independently of the logical check. -/
structure Engine where
  options : Executor.Options

private partial def retainedFiles (directory : System.FilePath) : IO (Array System.FilePath) := do
  let mut files := #[]
  for entry in ← directory.readDir do
    if ← entry.path.isDir then
      files := files ++ (← retainedFiles entry.path)
    else if entry.fileName != "check-result.json" then
      files := files.push entry.path
  return files
private def retentionFailure (result : Assessor.CheckResult) (message : String) : Assessor.CheckResult :=
  { result with
    status := .inconclusive, notRun := none, timedOut := false
    reasons := result.reasons.push message }

private def writeRetained (path : System.FilePath) (contents : String) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .write
  handle.putStr contents
  handle.flush

private def retainIn (directory : System.FilePath) (prepared : InputResult)
    (result : Assessor.CheckResult) : IO Assessor.CheckResult := do
  let (captured, inputSaved) ← try
    writeRetained (directory / "input.json") prepared.sourceText
    pure (result, true)
  catch error =>
    pure (retentionFailure result s!"could not retain prepared input: {error}", false)
  let retained ← try
    let files ← retainedFiles directory
    let files := if inputSaved then files else files.filter (· != directory / "input.json")
    pure { captured with evidence := #[directory] ++ files }
  catch error =>
    pure (retentionFailure captured s!"could not list check evidence: {error}")
  try
    writeRetained (directory / "check-result.json") (retained.toJson.pretty ++ "\n")
    return retained
  catch error =>
    return retentionFailure retained s!"could not retain check result: {error}"

private def retain (engine : Engine) (prepared : InputResult)
    (directory : Option System.FilePath) (result : Assessor.CheckResult) : IO Assessor.CheckResult := do
  let destination ← try
    let path ← match directory.or engine.options.directory with
      | some value => pure value
      | none => Executor.createRunDirectory engine.options.outputRoot
    pure (.ok path : Except String System.FilePath)
  catch error =>
    pure (.error s!"could not create check evidence directory: {error}")
  match destination with
  | .ok path => retainIn path prepared result
  | .error message => return retentionFailure result message

/-- Verify exactly one combination against an already prepared validator snapshot. -/
def Engine.verifyOne (engine : Engine) (prepared : InputResult)
    (check : Generator.ConfiguredCheck) : IO Assessor.CheckResult := do
  -- Reserve a configured workspace once so executor failures retain their raw files.
  let engine ← match engine.options.directory with
    | none => pure engine
    | some path =>
      try
        if let some parent := path.parent then IO.FS.createDirAll parent
        IO.FS.createDir path
        let directory ← IO.FS.realPath path
        pure { engine with options := { engine.options with directory := some directory } }
      catch error =>
        return retentionFailure (Assessor.failure prepared.target check.context
          "verification could not reserve its workspace") s!"could not create check evidence directory: {error}"
  match Generator.generateOne check prepared.target "Generated" with
  | .error error =>
    let result := Assessor.failure prepared.target check.context (toString error)
    let result := { result with notRun := if error.kind == .unsupported then some .unsupported else none }
    retain engine prepared none result
  | .ok plan =>
    match ← Executor.run plan engine.options with
    | .error message =>
      retain engine prepared none (Assessor.failure prepared.target check.context message)
    | .ok execution =>
      let result := Assessor.assessOne prepared.target check.context plan execution
      let notRun := if plan.status == .noObligations && plan.jobs.isEmpty && plan.modules.isEmpty &&
          execution.state == .noObligations && execution.jobs.isEmpty && execution.modules.isEmpty &&
          execution.problems.isEmpty && execution.retentionErrors.isEmpty then
        some Assessor.NotRunReason.notApplicable else none
      retain engine prepared execution.directory
        { result with notRun, timedOut := execution.state == .timedOut }

end Workflow.Verification

import Formal.Vesting.Linear.Tests.Audit
import Workflow.Executor.Process
import Workflow.Tests.Logging

namespace Formal.Vesting.Linear.Tests

open Lean Workflow.Executor

structure Check where
  name : String
  moduleName : String
  dependencies : Array String := #[]
  needsArtifact : Bool := false
  support : Bool := false
  deriving Inhabited

def checks : Array Check := #[
  { name := "Spec", moduleName := "Formal.Vesting.Linear.Spec" },
  { name := "Script", moduleName := "Formal.Vesting.Linear.Script", needsArtifact := true,
    support := true },
  { name := "Soundness", moduleName := "Formal.Vesting.Linear.Soundness",
    dependencies := #["Spec", "Script"], needsArtifact := true },
  { name := "Completeness", moduleName := "Formal.Vesting.Linear.Completeness",
    dependencies := #["Spec", "Script", "Soundness"], needsArtifact := true },
  { name := "Robustness", moduleName := "Formal.Vesting.Linear.Robustness",
    dependencies := #["Spec", "Script", "Soundness", "Completeness"], needsArtifact := true }]

structure Options where
  workingDirectory : System.FilePath := "."
  outputRoot : System.FilePath := "output"
  lakeCommand : String := "lake"
  timeoutMs : Nat := 300000
  checks : Array Check := checks

structure StepResult where
  name : String
  moduleName : String
  status : String := "NOT RUN"
  compiled : Bool := false
  elapsedMs : Nat := 0
  problem : Option String := none
  theorems : Array TheoremAudit := #[]
  deriving ToJson, FromJson, Inhabited

structure Result where
  directory : System.FilePath
  steps : Array StepResult
  exitCode : UInt32

abbrev RunProcess := Options → Nat → Array String → IO ProcessObservation

def runProcess : RunProcess := fun options deadline args =>
  Workflow.Executor.Process.run {
    leanPath := "", leanCommand := options.lakeCommand,
    workingDirectory := some options.workingDirectory }
    deadline args #[]

private def line := Workflow.Tests.Logging.line

private def processJson (observation : ProcessObservation) : Json := Json.mkObj [
  ("state", .str (match observation.state with
    | .finished => "finished" | .timedOut => "timedOut" | .launchError => "launchError")),
  ("exitCode", observation.exitCode.map (fun n => toJson n.toNat) |>.getD .null),
  ("elapsedMs", toJson observation.elapsedMs),
  ("invocation", observation.invocation.map Invocation.toJson |>.getD .null)]

private def observe (run : RunProcess) (options : Options) (deadline : Nat)
    (directory : System.FilePath) (stage : String) (args : Array String) : IO ProcessObservation := do
  line s!"  {stage}: {options.lakeCommand} {String.intercalate " " args.toList}"
  let observation ← run options deadline args
  IO.FS.writeFile (directory / s!"{stage}.stdout.log") observation.stdout
  IO.FS.writeFile (directory / s!"{stage}.stderr.log") observation.stderr
  IO.FS.writeFile (directory / s!"{stage}.process.json") ((processJson observation).pretty ++ "\n")
  for (label, contents) in #[ ("stdout", observation.stdout), ("stderr", observation.stderr) ] do
    line s!"--- {stage} {label} ---"
    line (if contents.isEmpty then "(empty)" else contents)
  return observation

private def processProblem (observation : ProcessObservation) : Option (String × String) :=
  if observation.state == .timedOut then some ("TIMEOUT", "execution budget exhausted")
  else if observation.state == .launchError then some ("ERROR", "process launch failed; inspect logs")
  else if observation.exitCode != some 0 then some ("ERROR", "command failed; inspect logs")
  else none

def assessAudit (check : Check) (audit : ModuleAudit) : Except String String := do
  unless audit.moduleName == check.moduleName do throw "audit module does not match the requested module"
  unless audit.theorems.all (fun t => #["PASS", "PENDING", "ERROR"].contains t.status) do
    throw "audit contains an unknown theorem status"
  unless audit.theorems.all (fun t =>
      axiomStatus (t.axioms.map String.toName) == t.status) do
    throw "audit status does not agree with the recorded axioms"
  if audit.theorems.any (·.status == "ERROR") then return "ERROR"
  if audit.theorems.any (·.status == "PENDING") then return "PENDING"
  if check.support then return "BUILT"
  if audit.theorems.isEmpty then throw "proof module audit contains no theorems"
  return "PASS"

private def auditSource (check : Check) (resultPath : System.FilePath) : String :=
  let identity := if check.name == "Script" then
      "#import_uplc observedMilestoneScript PlutusV3 flat_hex \"Scripts/linear_vesting_spend.flat\"\n" ++
      "example : Formal.Vesting.Linear.Script.spendValidator = observedMilestoneScript.script := by rfl\n"
    else ""
  s!"import {check.moduleName}\nimport Formal.Vesting.Linear.Tests.Audit\n\n" ++ identity ++
    s!"run_cmd Formal.Vesting.Linear.Tests.auditModule `{check.moduleName} {reprStr resultPath.toString}\n"

private def runCheck (run : RunProcess) (options : Options) (directory : System.FilePath)
    (check : Check) : IO StepResult := do
  let started ← IO.monoMsNow
  let deadline := started + options.timeoutMs
  let mut result : StepResult := { name := check.name, moduleName := check.moduleName }
  try
    IO.FS.createDirAll directory
    let build ← observe run options deadline directory "build" #["build", "+" ++ check.moduleName]
    if let some (status, problem) := processProblem build then
      return { result with status, problem := some problem, elapsedMs := (← IO.monoMsNow) - started }
    result := { result with compiled := true }
    let source := directory / "Audit.lean"
    let auditPath := directory / "audit.json"
    IO.FS.writeFile source (auditSource check auditPath)
    let audit ← observe run options deadline directory "audit" #["env", "lean", "--json", source.toString]
    if let some (status, problem) := processProblem audit then
      return { result with
        status, compiled := false, problem := some problem,
        elapsedMs := (← IO.monoMsNow) - started }
    let parsed ← match Json.parse (← IO.FS.readFile auditPath) >>= fromJson? (α := ModuleAudit) with
      | .ok parsed => pure parsed
      | .error problem => throw (IO.userError s!"invalid audit: {problem}")
    let status ← match assessAudit check parsed with
      | .ok status => pure status
      | .error problem => throw (IO.userError problem)
    return { result with
      status, compiled := status != "ERROR", theorems := parsed.theorems,
      elapsedMs := (← IO.monoMsNow) - started,
      problem := if status == "PENDING" then some "theorems depend on sorryAx; proof work remains"
        else if status == "ERROR" then some "theorems use an unapproved axiom" else none }
  catch error =>
    return { result with
      status := "ERROR", compiled := false, problem := some error.toString,
      elapsedMs := (← IO.monoMsNow) - started }

private def createDirectory (root : System.FilePath) : IO System.FilePath := do
  IO.FS.createDirAll root
  let root ← IO.FS.realPath root
  let output ← IO.Process.output { cmd := "mktemp", args := #["-d", (root / "m12.XXXXXXXX").toString] }
  unless output.exitCode == 0 do throw (IO.userError s!"could not create milestone output: {output.stderr}")
  return System.FilePath.mk output.stdout.trim

private def saveSummary (directory : System.FilePath) (options : Options)
    (steps : Array StepResult) (finished : Bool) : IO UInt32 := do
  let complete := finished && !steps.isEmpty && steps.all (fun s => s.status == "PASS" || s.status == "BUILT")
  let summary := Json.mkObj [
    ("suite", .str "M1.2 linear vesting"), ("finished", toJson finished),
    ("complete", toJson complete), ("timeoutMsPerStep", toJson options.timeoutMs),
    ("workingDirectory", .str options.workingDirectory.toString), ("steps", toJson steps)]
  IO.FS.writeFile (directory / "summary.json") (summary.pretty ++ "\n")
  let rows := steps.toList.map fun step =>
    s!"{step.status}: {step.name} ({step.elapsedMs} ms)" ++
      (step.problem.map (fun p => "\n  " ++ p)).getD ""
  let text := "M1.2 linear vesting: " ++ (if complete then "complete" else "incomplete") ++ "\n\n" ++
    String.intercalate "\n" rows ++ "\n\n" ++
    "PASS: module theorems checked within their existing claims and trust assumptions.\n" ++
    "BUILT: support module compiled and its script identity checked; not a proof result.\n" ++
    "PENDING: one or more theorems depend on sorryAx.\n" ++
    "BLOCKED: missing artifact or an unavailable dependency.\n" ++
    "TIMEOUT: the shared build/audit budget expired. ERROR: command, audit, or evidence failure.\n" ++
    "NOT RUN: no result has been recorded for this step.\n" ++
    "Blaster proofs retain the existing SMT trust boundary; see each theorem's axiom list.\n"
  IO.FS.writeFile (directory / "summary.txt") text
  return if complete then 0 else 2

private def retainInputs (options : Options) (directory : System.FilePath) : IO Unit := do
  for name in #["lean-toolchain", "lake-manifest.json", "lakefile.toml"] do
    let source := options.workingDirectory / name
    if ← source.pathExists then
      IO.FS.writeFile (directory / name) (← IO.FS.readFile source)

private def artifactDigest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {
    cmd := "timeout", args := #["--signal=KILL", "5s", "sha256sum", path.toString], setsid := true }
  unless result.exitCode == 0 do throw (IO.userError s!"could not hash milestone artifact: {result.stderr}")
  return result.stdout.trim

/-- Controlled tests may substitute subprocesses; the default suite always uses the five modules above. -/
def runWith (options : Options := {}) (run : RunProcess := runProcess) : IO Result := do
  unless options.timeoutMs > 0 do throw (IO.userError "--timeout-ms must be positive")
  let cwd ← IO.FS.realPath options.workingDirectory
  let options := { options with workingDirectory := cwd }
  let outputRoot := if options.outputRoot.isAbsolute then options.outputRoot else cwd / options.outputRoot
  let directory ← createDirectory outputRoot
  line s!"M1.2 linear vesting tests\nOutput: {directory}\nBudget: {options.timeoutMs} ms per module (build and audit)"
  let mut steps := options.checks.map fun check =>
    { name := check.name, moduleName := check.moduleName : StepResult }
  let _ ← saveSummary directory options steps false
  try
    retainInputs options directory
    let artifact := cwd / "Scripts/linear_vesting_spend.flat"
    let artifactPresent ← artifact.pathExists
    let digest ← if artifactPresent then some <$> artifactDigest artifact else pure none
    IO.FS.writeFile (directory / "artifact.json") ((Json.mkObj [
      ("path", .str artifact.toString), ("present", toJson artifactPresent),
      ("sha256sum", digest.map Json.str |>.getD .null),
      ("provenance", .str "Existing local flat artifact; no source-to-byte provenance is asserted.")]).pretty ++ "\n")
    for index in [:options.checks.size] do
      let check := options.checks[index]!
      line s!"START {check.name}: {check.moduleName}"
      let blocked := if check.needsArtifact && !artifactPresent then
          some "missing Scripts/linear_vesting_spend.flat; prepare the intended milestone artifact separately"
        else if check.dependencies.any (fun dep => !steps.any (fun s => s.name == dep && s.compiled)) then
          some "a required module did not compile and complete its audit"
        else none
      let result ← match blocked with
        | some problem => pure {
            name := check.name, moduleName := check.moduleName,
            status := "BLOCKED", problem := some problem : StepResult }
        | none => runCheck run options (directory / check.name) check
      steps := steps.set! index result
      line s!"FINISH {check.name}: {result.status} ({result.elapsedMs} ms)"
      if let some problem := result.problem then line s!"  {problem}"
      for entry in result.theorems do line s!"  {entry.status}: {entry.name}"
      let _ ← saveSummary directory options steps false
    if let some before := digest then
      unless (← artifactDigest artifact) == before do
        throw (IO.userError "milestone artifact changed during the run; results cannot be attributed reliably")
    let exitCode ← saveSummary directory options steps true
    line (← IO.FS.readFile (directory / "summary.txt"))
    line s!"Summary: {directory / "summary.json"}"
    return { directory, steps, exitCode }
  catch error =>
    IO.FS.writeFile (directory / "run-error.txt") (error.toString ++ "\n")
    let _ ← saveSummary directory options steps false
    line s!"ERROR: {error}\nIncomplete evidence: {directory}"
    return { directory, steps, exitCode := 2 }

end Formal.Vesting.Linear.Tests

import Lean.Data.Json
import Workflow.Tests.Logging

namespace Workflow.Tests.Runner

open Lean

structure Suite where
  name : String
  executable : String
  deriving Inhabited

def defaultSuites : Array Suite := #[
  ⟨"Input unit checks", "workflow_input_tests"⟩,
  ⟨"Generator unit checks", "workflow_generator_tests"⟩,
  ⟨"Reusable input compatibility and program preparation", "workflow_preparation_tests"⟩,
  ⟨"Executor unit checks", "workflow_executor_tests"⟩,
  ⟨"Reporter unit checks", "workflow_reporter_tests"⟩,
  ⟨"Property metadata checks", "workflow_metadata_tests"⟩,
  ⟨"Run evidence checks", "workflow_evidence_tests"⟩,
  ⟨"Single-check core and app solver checks", "workflow_single_check_tests"⟩,
  ⟨"CLI selection checks", "workflow_selection_tests"⟩,
  ⟨"Installer and launcher checks", "workflow_installation_tests"⟩,
  ⟨"Blueprint orchestration and output checks", "workflow_app_tests"⟩,
  ⟨"Shared source capture and compilation checks", "workflow_sources_tests"⟩,
  ⟨"Review index and portable links", "workflow_review_tests"⟩,
  ⟨"Test-runner controls", "workflow_runner_tests"⟩,
  ⟨"Input-to-Generator integration", "workflow_generator_integration"⟩,
  ⟨"Executor solver integration", "workflow_executor_integration"⟩,
  ⟨"Reporter solver integration", "workflow_reporter_integration"⟩,
  ⟨"UP-001 whole-workflow scenario", "workflow_up001_tests"⟩,
  ⟨"UP-012 whole-workflow scenario", "workflow_up012_tests"⟩,
  ⟨"UP-015 shared-model output-swap scenario", "workflow_up015_tests"⟩]

/-- Small programmatic seam for the runner's own controlled failure tests. -/
structure Options where
  lakeCommand : String := "lake"
  binaryDirectory : System.FilePath := ".lake/build/bin"
  outputRoot : System.FilePath := "output"
  suites : Array Suite := defaultSuites

private structure Step where
  name : String
  command : Array String
  state : String := "notRun"
  exitCode : Option UInt32 := none
  elapsedMs : Nat := 0
  stdoutLog : Option System.FilePath := none
  stderrLog : Option System.FilePath := none
  problem : Option String := none

private def commandText (command : Array String) : String :=
  String.intercalate " " (command.toList.map reprStr)

private def stateText (state : String) : String :=
  if state == "passed" then "PASS" else if state == "failed" then "FAIL" else "NOT RUN"

private def stepJson (step : Step) : Json := Json.mkObj [
  ("name", .str step.name), ("command", toJson step.command), ("state", .str step.state),
  ("exitCode", step.exitCode.map (fun value => toJson value.toNat) |>.getD .null),
  ("elapsedMs", toJson step.elapsedMs),
  ("stdoutLog", step.stdoutLog.map (fun path => Json.str path.toString) |>.getD .null),
  ("stderrLog", step.stderrLog.map (fun path => Json.str path.toString) |>.getD .null),
  ("problem", step.problem.map Json.str |>.getD .null)]

private def stepText (step : Step) : String :=
  let exit := step.exitCode.map (fun value => toString value.toNat) |>.getD "none"
  String.intercalate "\n" [
    s!"{stateText step.state}: {step.name} (exit {exit}, {step.elapsedMs} ms)",
    s!"  Command: {commandText step.command}",
    s!"  stdout: {(step.stdoutLog.map (·.toString)).getD "none"}",
    s!"  stderr: {(step.stderrLog.map (·.toString)).getD "none"}",
    s!"  Problem: {step.problem.getD "none"}"]

private def saveSummary (directory cwd : System.FilePath) (elapsedMs : Nat)
    (build : Step) (suites : Array Step) (finished : Bool) : IO Unit := do
  let passed := build.state == "passed" && !suites.isEmpty && suites.all (·.state == "passed")
  let status := if !finished then "running" else if passed then "passed" else "failed"
  let summary := Json.mkObj [
    ("product", .str "Plutus UPV"), ("status", .str status), ("cwd", .str cwd.toString),
    ("elapsedMs", toJson elapsedMs), ("build", stepJson build),
    ("suites", .arr (suites.map stepJson))]
  IO.FS.writeFile (directory / "summary.json") (summary.pretty ++ "\n")
  let text := String.intercalate "\n\n" [
    s!"Plutus UPV workflow tests: {status}",
    s!"Output: {directory}\nWorking directory: {cwd}\nElapsed: {elapsedMs} ms",
    "Control reports may intentionally say FAIL or INCONCLUSIVE. Suite exit codes determine test success.",
    stepText build,
    String.intercalate "\n\n" (suites.toList.map stepText)]
  IO.FS.writeFile (directory / "summary.txt") (text ++ "\n")

private def createDirectory (root : System.FilePath) : IO System.FilePath := do
  IO.FS.createDirAll root
  let root ← IO.FS.realPath root
  let output ← IO.Process.output { cmd := "mktemp", args := #["-d", (root / "test.XXXXXXXX").toString] }
  unless output.exitCode == 0 do throw (IO.userError s!"could not create test log directory: {output.stderr.trim}")
  return System.FilePath.mk output.stdout.trim

private def runStep (directory : System.FilePath) (key name : String)
    (args : IO.Process.SpawnArgs) : IO Step := do
  let command := #[args.cmd] ++ args.args
  let stdoutLog := directory / s!"{key}.stdout.log"
  let stderrLog := directory / s!"{key}.stderr.log"
  Logging.line s!"START {name}"
  Logging.line s!"  Command: {commandText command}"
  Logging.line s!"  stdout: {stdoutLog}\n  stderr: {stderrLog}"
  let started ← IO.monoMsNow
  try
    let output ← Logging.run args (some stdoutLog) (some stderrLog)
    let elapsedMs := (← IO.monoMsNow) - started
    let state := if output.exitCode == 0 then "passed" else "failed"
    Logging.line s!"FINISH {name}: {stateText state} (exit {output.exitCode}, {elapsedMs} ms)"
    return { name, command, state, exitCode := some output.exitCode, elapsedMs,
             stdoutLog := some stdoutLog, stderrLog := some stderrLog }
  catch error =>
    let elapsedMs := (← IO.monoMsNow) - started
    Logging.line s!"FINISH {name}: FAIL (launch/output error, {elapsedMs} ms): {error}"
    return { name, command, state := "failed", elapsedMs,
             stdoutLog := some stdoutLog, stderrLog := some stderrLog, problem := some error.toString }

def runWith (options : Options) : IO UInt32 := do
  try
    let started ← IO.monoMsNow
    let cwd ← IO.FS.realPath (← IO.currentDir)
    let directory ← createDirectory options.outputRoot
    Logging.line "Plutus UPV: all workflow tests"
    Logging.line s!"Logs and summary: {directory}"
    Logging.line "Expected controls can print FAIL or INCONCLUSIVE; only unexpected suite failures fail this command."
    let buildArgs : IO.Process.SpawnArgs := {
      cmd := options.lakeCommand, cwd := some cwd,
      args := #["build", "plutus-upv"] ++ options.suites.map (·.executable) }
    let mut suites := options.suites.map fun suite =>
      { name := suite.name,
        command := #[(options.binaryDirectory / suite.executable).toString] : Step }
    let build ← runStep directory "build" "Build workflow test executables" buildArgs
    if build.state != "passed" then
      suites := suites.map fun suite => { suite with problem := some "build failed; suite was not run" }
      saveSummary directory cwd ((← IO.monoMsNow) - started) build suites true
      Logging.line "Build failed. No test executables were run."
      Logging.line s!"Summary: {directory / "summary.txt"}"
      return 1
    saveSummary directory cwd ((← IO.monoMsNow) - started) build suites false
    for index in [:options.suites.size] do
      let suite := options.suites[index]!
      let result ← runStep directory s!"suite-{index + 1}" suite.name {
        cmd := (options.binaryDirectory / suite.executable).toString, cwd := some cwd }
      suites := suites.set! index result
      saveSummary directory cwd ((← IO.monoMsNow) - started) build suites (index + 1 == options.suites.size)
    let passed := !suites.isEmpty && suites.all (·.state == "passed")
    if suites.isEmpty then
      saveSummary directory cwd ((← IO.monoMsNow) - started) build suites true
    let successes := (suites.filter (·.state == "passed")).size
    Logging.line s!"FINISH Plutus UPV: {successes}/{suites.size} suites passed"
    Logging.line s!"Summary: {directory / "summary.txt"}"
    return if passed then 0 else 1
  catch error =>
    Logging.line s!"Plutus UPV test runner failed: {error}"
    return 1

def run : IO UInt32 := runWith {}

end Workflow.Tests.Runner

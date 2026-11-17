import Lean.Data.Json

namespace Formal.Shared.Process

inductive ProcessState where
  | finished | timedOut | launchError
  deriving BEq, Repr

/-- An attempted process invocation and its explicit environment overrides. -/
structure Invocation where
  command : String
  args : Array String
  cwd : System.FilePath
  environment : Array (String × Option String)

def Invocation.toJson (invocation : Invocation) : Lean.Json := Lean.Json.mkObj [
  ("command", .str invocation.command), ("args", Lean.toJson invocation.args),
  ("cwd", .str invocation.cwd.toString),
  ("environment", .arr (invocation.environment.map fun (name, value) => Lean.Json.mkObj [
    ("name", .str name), ("value", value.map Lean.Json.str |>.getD .null)]))]

structure ProcessObservation where
  state : ProcessState
  exitCode : Option UInt32 := none
  stdout : String := ""
  stderr : String := ""
  elapsedMs : Nat := 0
  invocation : Option Invocation := none

structure Options where
  command : String
  timeoutCommand : String := "timeout"
  /-- Override the child working directory without mutating the parent process. -/
  workingDirectory : Option System.FilePath := none

private def duration (milliseconds : Nat) : String :=
  let fraction := toString (milliseconds % 1000)
  let fraction := if fraction.length == 1 then "00" ++ fraction
    else if fraction.length == 2 then "0" ++ fraction else fraction
  s!"{milliseconds / 1000}.{fraction}s"

/-- GNU timeout owns the command's process group and hard-kills it at the deadline. -/
def run (options : Options) (deadline : Nat) (args : Array String)
    (environment : Array (String × Option String)) : IO ProcessObservation := do
  let started ← IO.monoMsNow
  if started ≥ deadline then return { state := .timedOut }
  try
    let attempted : Invocation := {
      command := options.timeoutCommand
      args := #["--signal=KILL", duration (deadline - started), options.command] ++ args
      cwd := options.workingDirectory.getD (← IO.currentDir)
      environment }
    let observed : ProcessObservation ← try
      let output ← IO.Process.output {
        cmd := attempted.command
        args := attempted.args
        cwd := some attempted.cwd
        env := attempted.environment
        setsid := true }
      let finished ← IO.monoMsNow
      pure {
        state := if finished ≥ deadline then .timedOut else .finished
        exitCode := some output.exitCode
        stdout := output.stdout
        stderr := output.stderr
        elapsedMs := finished - started
        invocation := some attempted }
    catch error =>
      pure {
        state := .launchError
        stderr := error.toString
        elapsedMs := (← IO.monoMsNow) - started
        invocation := some attempted }
    return observed
  catch error =>
    return { state := .launchError, stderr := error.toString
             elapsedMs := (← IO.monoMsNow) - started }

end Formal.Shared.Process

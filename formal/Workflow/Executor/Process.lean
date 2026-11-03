import Workflow.Executor.Types

namespace Workflow.Executor.Process

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
      args := #["--signal=KILL", duration (deadline - started), options.leanCommand] ++ args
      cwd := ← IO.currentDir
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

end Workflow.Executor.Process

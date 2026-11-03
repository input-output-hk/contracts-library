import Workflow.Input
import Workflow.Generator
import Candidates.UP001
import Workflow.Tests.Unit.Executor.Controls
import Formal.Universal.Properties

open Workflow

namespace Workflow.Tests.UP001.ExecutorIntegration

def run (args : List String) : IO Unit := do
  let environment ← IO.Process.output { cmd := "lake", args := #["env", "printenv", "LEAN_PATH"] }
  unless environment.exitCode == 0 do throw (IO.userError environment.stderr)
  let leanPath := environment.stdout.trim
  Workflow.Tests.Unit.Executor.Controls.run leanPath
  match args with
  | [] => pure ()
  | [path, selector, budgetText] =>
    let some budget := budgetText.toNat? | throw (IO.userError "budget must be positive milliseconds")
    let input ← match ← Input.read path selector with
      | .ok value => pure value
      | .error error => throw (IO.userError (toString error))
    let plan ← match Generator.generate Candidates.UP001.provider input.target "Executed.Validator" with
      | .ok value => pure value
      | .error error => throw (IO.userError (toString error))
    let result ← Workflow.Tests.Unit.Executor.Controls.execute plan leanPath budget
    if let some directory := result.directory then
      IO.FS.writeFile (directory / "input.json") input.sourceText
    IO.println s!"{input.target.name}: {reprStr result.state}; {result.elapsedMs} ms; evidence: {(result.directory.map (·.toString)).getD "none"}"
    IO.println s!"Observed: {(result.jobs.filter (·.observed == .valid)).size} Valid, {(result.jobs.filter (·.observed == .falsified)).size} Falsified, {(result.jobs.filter (·.observed == .inconclusive)).size} inconclusive"
    if result.state == .error then throw (IO.userError (String.intercalate "\n" result.problems.toList))
  | _ => throw (IO.userError "usage: workflow_executor_integration [BLUEPRINT VALIDATOR BUDGET_MS]")


end Workflow.Tests.UP001.ExecutorIntegration

def main (args : List String) : IO Unit := Workflow.Tests.UP001.ExecutorIntegration.run args

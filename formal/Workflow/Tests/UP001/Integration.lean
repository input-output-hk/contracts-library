import Workflow.Input
import Workflow.Generator
import Candidates.UP001
import Formal.Universal.Properties

open Workflow

namespace Workflow.Tests.UP001.Integration

private def compileModule (directory : System.FilePath) (leanPath : String)
    (source : GeneratedModule) : IO Unit := do
  let path := directory / (source.name.replace "." "/" ++ ".lean")
  IO.FS.createDirAll (path.parent.getD directory)
  IO.FS.writeFile path source.source
  let result ← IO.Process.output {
    cmd := "lean"
    args := #[s!"--root={directory}", "-o", path.withExtension "olean" |>.toString, path.toString]
    env := #[("LEAN_PATH", some s!"{directory}:{leanPath}")] }
  unless result.exitCode == 0 do
    throw (IO.userError s!"generated module {source.name} failed:\n{result.stdout}{result.stderr}")

/-- Type-check the emitted propositions without discharging them or invoking Blaster. -/
private def statements (plan : GenerationPlan) (modulePrefix : String) : GeneratedModule :=
  let body := String.intercalate "\n" (plan.jobs.toList.map fun job =>
    s!"def {job.name}_statement : Prop :=\n{job.statement}\n")
  { name := s!"{modulePrefix}.Statements"
    source := String.intercalate "\n" [
      s!"import {modulePrefix}.Types", "import Formal.Universal.Properties",
      "import Formal.Properties.Universal.UP001.Definition", "",
      s!"namespace {modulePrefix}", "open PlutusCore.Data (Data)",
      "open Formal.Universal.Properties", body, s!"end {modulePrefix}", ""] }

private def exercise (directory : System.FilePath) (leanPath : String)
    (path : System.FilePath) (selector modulePrefix : String) : IO Unit := do
  let original ← IO.FS.readFile path
  let input ← match ← Input.read path selector with
    | .ok value => pure value
    | .error error => throw (IO.userError (toString error))
  let plan ← match Workflow.Generator.generate Candidates.UP001.provider input.target modulePrefix with
    | .ok value => pure value
    | .error error => throw (IO.userError (toString error))
  unless plan.status == .ready && plan.jobs.size == 5 do
    throw (IO.userError "expected five undeclared-purpose obligations")
  let some support := plan.modules[0]? | throw (IO.userError "missing support module")
  compileModule directory leanPath support
  compileModule directory leanPath (statements plan modulePrefix)
  unless (← IO.FS.readFile path) == original && input.sourceText == original do
    throw (IO.userError "source artifact changed")
  IO.println s!"{input.target.name}: generated support and {plan.jobs.size} statements type-check."

def run (args : List String) : IO Unit := do
  let environment ← IO.Process.output { cmd := "lake", args := #["env", "printenv", "LEAN_PATH"] }
  unless environment.exitCode == 0 do throw (IO.userError environment.stderr)
  IO.FS.withTempDir fun directory => do
    exercise directory environment.stdout.trim "Workflow/Tests/Unit/Input/Fixtures/blueprint.json"
      "other.beta" "Generated.Fixture"
    match args with
    | [] => pure ()
    | [path, selector] =>
      exercise directory environment.stdout.trim (System.FilePath.mk path) selector "Generated.Real"
    | _ => throw (IO.userError "usage: workflow_generator_integration [BLUEPRINT VALIDATOR]")
  IO.println "Input-to-Generator integration passed; no solver proofs ran."

end Workflow.Tests.UP001.Integration

def main (args : List String) : IO Unit := Workflow.Tests.UP001.Integration.run args

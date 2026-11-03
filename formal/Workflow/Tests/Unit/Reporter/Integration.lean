import Workflow.Reporter
import Workflow.Executor
import Blaster

open Workflow

def main : IO Unit := do
  let environment ← IO.Process.output { cmd := "lake", args := #["env", "printenv", "LEAN_PATH"] }
  unless environment.exitCode == 0 do throw (IO.userError environment.stderr)
  let source ← IO.FS.readFile "Workflow/Tests/Unit/Fixtures/outcomes.lean.txt"
  for expectedBad in [ExpectedResult.falsified, .valid] do
    let plan : GenerationPlan := {
      targetName := "reporter-controls", modules := #[⟨"Controls.Report", source⟩]
      jobs := #[
        { propertyId := "fixture", name := "good", moduleName := "Controls.Report",
          statement := "∀ x : Int, x = x", expected := .valid, scope := "arithmetic fixture only" },
        { propertyId := "fixture", name := "bad", moduleName := "Controls.Report",
          statement := "∀ x : Int, x = 0", expected := expectedBad, scope := "arithmetic fixture only" }] }
    let result ← match ← Executor.run plan { leanPath := environment.stdout.trim, budgetMs := 15000 } with
      | .ok value => pure value
      | .error message => throw (IO.userError message)
    let report := Reporter.build plan result
    let expectedCode : UInt32 := if expectedBad == .falsified then 0 else 1
    unless report.exitCode == expectedCode do
      throw (IO.userError s!"unexpected report exit code: {report.text}")
    let some directory := result.directory | throw (IO.userError "missing solver evidence")
    report.write directory
    IO.print report.text
    IO.println s!"Report: {directory / "report.json"}"
  let qualifiedPlan : GenerationPlan := {
    targetName := "applicability-controls", modules := #[⟨"Controls.Applicability", source⟩]
    jobs := #[
      { propertyId := "fixture", name := "good", moduleName := "Controls.Applicability",
        statement := "∀ x : Int, x = x", expected := .valid, scope := "arithmetic qualification fixture only"
        applicability := some { moduleName := "Controls.Applicability", name := "bad" } },
      { propertyId := "fixture", name := "bad", moduleName := "Controls.Applicability",
        statement := "∀ x : Int, x = 0", expected := .valid, scope := "arithmetic qualification fixture only"
        role := .applicability }] }
  let result ← match ← Executor.run qualifiedPlan { leanPath := environment.stdout.trim, budgetMs := 15000 } with
    | .ok value => pure value
    | .error message => throw (IO.userError message)
  let report := Reporter.build qualifiedPlan result
  unless report.exitCode == 2 && report.rows.size == 2 &&
      report.rows.all (·.status == .inconclusive) &&
      report.rows.any (fun row => row.job.name == "good" && row.observed == some .valid) &&
      report.rows.any (fun row => row.job.name == "bad" && row.observed == some .falsified) do
    throw (IO.userError s!"false applicability did not qualify the report correctly: {report.text}")
  let some directory := result.directory | throw (IO.userError "missing qualification evidence")
  report.write directory
  IO.print report.text
  IO.println s!"Report: {directory / "report.json"}"
  IO.println "Reporter real-solver integration passed."

import Workflow.Executor

open Workflow

namespace Workflow.Tests.Unit.Executor.Controls

def execute (plan : GenerationPlan) (leanPath : String) (budget : Nat) : IO Executor.Result := do
  match ← Executor.run plan { leanPath, budgetMs := budget } with
  | .ok result => return result
  | .error message => throw (IO.userError message)

def run (leanPath : String) : IO Unit := do
  let source ← IO.FS.readFile "Workflow/Tests/Unit/Fixtures/outcomes.lean.txt"
  let controls : GenerationPlan := {
    targetName := "executor-controls", modules := #[⟨"Controls.Outcomes", source⟩]
    jobs := #[
      { propertyId := "fixture-valid", name := "good", moduleName := "Controls.Outcomes",
        statement := "∀ x : Int, x = x", expected := .valid, scope := "fixture only" },
      { propertyId := "fixture-falsified", name := "bad", moduleName := "Controls.Outcomes",
        statement := "∀ x : Int, x = 0", expected := .falsified, scope := "fixture only" }] }
  let controlResult ← execute controls leanPath 15000
  unless controlResult.state == .completed && controlResult.jobs.size == 2 &&
      controlResult.jobs.any (fun item => item.job.name == "good" && item.observed == .valid) &&
      controlResult.jobs.any (fun item => item.job.name == "bad" && item.observed == .falsified) do
    throw (IO.userError s!"real solver controls failed; evidence: {reprStr (controlResult.directory.map (·.toString))}")
  IO.println s!"Real solver controls observed Valid and Falsified; evidence: {(controlResult.directory.map (·.toString)).getD "none"}"

end Workflow.Tests.Unit.Executor.Controls

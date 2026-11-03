import Workflow.Tests.UP001.DefinitionEquivalence
import Workflow.Generator
import Candidates.UP001

open Lean Workflow
open Workflow.Generator

namespace Workflow.Tests.UP001.Tests

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def target (purposes : Array Purpose := #[.spend]) : TargetDescription :=
  { name := "fixture.target", plutusVersion := "v3", compiledCode := "480100002221200101"
    handlers := purposes.map fun p =>
      { name := s!"fixture.target.{p.name}", purpose := some p,
        datum := none, redeemer := none, declaredHash := none }
    parameters := none, definitions := none, compiler := none }

private def accepted (input : TargetDescription) (modulePrefix := "Generated.Positive") :
    IO GenerationPlan := do
  match generate Candidates.UP001.provider input modulePrefix with
  | .ok plan => return plan
  | .error error => throw (IO.userError s!"unexpected generator error: {error}")

def run : IO Unit := do
  let plan ← accepted target
  check "target identity retained" (plan.targetName == target.name)
  check "generation ready" (plan.status == .ready)
  check "support and check modules" (plan.modules.size == 2)
  check "five undeclared purposes" (plan.jobs.size == 5)
  check "declared spend excluded" (plan.jobs.all (·.name != "otherPurpose_spend"))
  check "expectation belongs to jobs" (plan.jobs.all (·.expected == .valid))
  check "scope records fuel semantics" (plan.jobs.all (·.scope == plan.notes[0]!))
  check "scope reports the reviewed bound" ((plan.notes[0]!.splitOn "5,000,000 CEK steps").length == 2)
  let golden ← IO.FS.readFile "Workflow/Tests/UP001/Expected/declarations.lean.txt"
  let declarations := String.intercalate "\n" (plan.jobs.toList.map fun job =>
    s!"theorem {job.name} :\n{job.statement} := by\n  unfold Formal.Properties.Universal.UP001.statement\n  blaster\n")
  check "shared-definition applications match reviewed declarations" (declarations.trim == golden.trim)
  let some types := plan.modules[0]? | throw (IO.userError "missing types module")
  let some checks := plan.modules[1]? | throw (IO.userError "missing checks module")
  check "encoded artifact embedded" ((types.source.splitOn target.compiledCode).length == 2)
  check "jobs and rendered checks agree" (plan.jobs.all fun job =>
    (checks.source.splitOn s!"theorem {job.name} :\n{job.statement} := by\n  unfold Formal.Properties.Universal.UP001.statement\n  blaster").length == 2)
  check "no statement fixture proof bypass" ((checks.source.splitOn "sorry").length == 1)

  let noneDeclared ← accepted (target #[])
  check "all six purposes can be checked" (noneDeclared.jobs.size == 6)
  let allDeclared ← accepted (target #[.spend, .mint, .withdraw, .publish, .vote, .propose])
  check "empty is explicit, not success" (allDeclared.status == .noObligations &&
    allDeclared.jobs.isEmpty && allDeclared.modules.isEmpty && !allDeclared.notes.isEmpty)
  let emptyParams ← accepted { target with parameters := some #[] }
  check "explicit empty parameter list is supported" (emptyParams.jobs.size == 5)
  let parameter : ArgumentDescription :=
    { schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
  match generate Candidates.UP001.provider { target with parameters := some #[parameter] } "Generated.Params" with
  | .error error => check "parameters are explicitly unsupported" (error.kind == .unsupported)
  | .ok _ => throw (IO.userError "parameterized target silently changed scope")
  match generate Candidates.UP001.provider { target with plutusVersion := "v2" } "Generated.Version" with
  | .error error => check "unsupported version is explicit" (error.kind == .unsupported)
  | .ok _ => throw (IO.userError "unsupported version accepted")
  for invalid in ["", ".Broken", "lower.Case", "Generated.Type", "Generated.X;#eval"] do
    match generate Candidates.UP001.provider target invalid with
    | .error error => check "unsafe module prefix rejected" (error.kind == .invalidNamespace)
    | .ok _ => throw (IO.userError s!"unsafe module prefix accepted: {invalid}")

  IO.println "UP-001 generator checks passed."

end Workflow.Tests.UP001.Tests

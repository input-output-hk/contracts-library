import Workflow.Generator

open Lean Workflow
open Workflow.Generator

namespace Workflow.Tests.Unit.Generator

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def target (purposes : Array Purpose := #[.spend]) : TargetDescription :=
  { name := "fixture.target", plutusVersion := "v3", compiledCode := "480100002221200101"
    handlers := purposes.map fun p =>
      { name := s!"fixture.target.{p.name}", purpose := some p,
        datum := none, redeemer := none, declaredHash := none }
    parameters := none, definitions := none, compiler := none }

def run : IO Unit := do
  let sampleProvider : Provider := {
    id := "fixture-witness"
    generate := fun input modulePrefix => .ok {
      targetName := input.name
      modules := #[⟨s!"{modulePrefix}.Checks", "-- fixture source\n"⟩]
      jobs := #[{ propertyId := "fixture-witness", name := "witness",
                  moduleName := s!"{modulePrefix}.Checks", statement := "False",
                  expected := .falsified, scope := "fixture only" }] } }
  match generate sampleProvider target "Generated.Other" with
  | .ok result =>
    let some job := result.jobs[0]? | throw (IO.userError "missing sample job")
    check "engine accepts another provider and expectation"
      (result.status == .ready && job.propertyId == "fixture-witness" && job.expected == .falsified)
  | .error error => throw (IO.userError (toString error))
  for invalid in ["", ".Broken", "lower.Case", "Generated.Type", "Generated.X;#eval"] do
    match generate sampleProvider target invalid with
    | .error error => check "unsafe module prefix rejected" (error.kind == .invalidNamespace)
    | .ok _ => throw (IO.userError s!"unsafe module prefix accepted: {invalid}")

  let emptyProvider : Provider := {
    id := "empty-fixture"
    generate := fun input _ => .ok { targetName := input.name, modules := #[], jobs := #[] } }
  match generate emptyProvider target "Generated.Empty" with
  | .ok result => check "empty plan is explicit" (result.status == .noObligations && result.jobs.isEmpty)
  | .error error => throw (IO.userError (toString error))
  IO.println "Generic Generator checks passed."

end Workflow.Tests.Unit.Generator

def main : IO Unit := Workflow.Tests.Unit.Generator.run

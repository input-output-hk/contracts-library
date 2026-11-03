import Workflow.Tests.UP012.DefinitionEquivalence
import Workflow.Generator
import Workflow.Input
import Workflow.Tests.UP012.Profile
import Candidates.Catalogue

open Lean Workflow
open Workflow.Generator

namespace Workflow.Tests.UP012.Tests

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def target (purposes : Array Purpose := #[.spend]) : TargetDescription :=
  { name := "fixture.target", plutusVersion := "v3", compiledCode := "480100002221200101"
    handlers := purposes.map fun p =>
      { name := s!"fixture.target.{p.name}", purpose := some p,
        datum := none, redeemer := none, declaredHash := none }
    parameters := none, definitions := none, compiler := none }

def run : IO Unit := do
  let parameter : ArgumentDescription :=
    { schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
  let referenceCode ← IO.FS.readFile "Workflow/Tests/UP012/Inputs/compiled-code.txt"
  let vesting := { target with compiledCode := referenceCode.trim }
  let signerPlan ← match generate Workflow.Tests.UP012.Profile.provider vesting "Generated.Signers" with
    | .ok value => pure value
    | .error error => throw (IO.userError (toString error))
  check "UP-012 has support, shapes, and checks" (signerPlan.modules.size == 3 && signerPlan.jobs.size == 4)
  check "UP-012 keeps applicability jobs" ((signerPlan.jobs.filter (·.role == .applicability)).size == 2)
  check "UP-012 uses declared Valid expectations" (signerPlan.jobs.all (·.expected == .valid))
  for (propertyName, applicabilityName) in [
      ("dropSigner_claim", "dropSigner_claim_applies"),
      ("dropSigner_cancel", "dropSigner_cancel_applies")] do
    let some propertyJob := signerPlan.jobs.find? (·.name == propertyName)
      | throw (IO.userError s!"missing property obligation: {propertyName}")
    let some applicabilityJob := signerPlan.jobs.find? (·.name == applicabilityName)
      | throw (IO.userError s!"missing applicability obligation: {applicabilityName}")
    let reference : JobRef := { moduleName := "Generated.Signers.Checks", name := applicabilityName }
    check s!"{propertyName}: explicit property role and action-specific qualification"
      (propertyJob.role == .property && propertyJob.applicability == some reference)
    check s!"{applicabilityName}: explicit applicability role without another dependency"
      (applicabilityJob.role == .applicability && applicabilityJob.applicability.isNone &&
       applicabilityJob.expected == .valid)
  let signerGolden ← IO.FS.readFile "Workflow/Tests/UP012/Expected/declarations.lean.txt"
  let signerDeclarations := String.intercalate "\n" (signerPlan.jobs.toList.map fun job =>
    s!"theorem {job.name} :\n{job.statement} := by blaster\n")
  check "UP-012 instantiates the shared property and applicability definitions" (signerDeclarations.trim == signerGolden.trim)
  check "UP-012 embeds code instead of reading Scripts"
    (signerPlan.modules.all fun source => (source.source.splitOn "#import_uplc").length == 1)
  check "UP-001 remains the default provider" ((Candidates.Catalogue.selectProvider none).toOption.map (·.id) == some "UP-001")
  check "UP-012 is selectable" ((Candidates.Catalogue.selectProvider (some "UP-012")).toOption.map (·.id) == some "UP-012")
  for unsupported in [target, { vesting with parameters := some #[parameter] },
      { vesting with plutusVersion := "v2" }, { vesting with handlers := #[] }] do
    match generate Workflow.Tests.UP012.Profile.provider unsupported "Generated.Unsupported" with
    | .error error => check "UP-012 profile restrictions are explicit" (error.kind == .unsupported)
    | .ok _ => throw (IO.userError "UP-012 accepted an unsupported profile")
  for (fixture, expectedHash) in [
      ("Workflow/Tests/UP012/Inputs/plutus.json",
       "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a"),
      ("Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json",
       "114e35c85d59745cb61ba73e1a9192467a4dae666a286a45f97a15f8")] do
    let input ← IO.ofExcept ((← Input.read fixture "linear_vesting.linear_vesting").mapError toString)
    -- Supplied metadata must not choose the generated script hash.
    let accepted := { input.target with
      handlers := input.target.handlers.map fun h => { h with declaredHash := some "untrusted" } }
    let plan ← IO.ofExcept ((generate Workflow.Tests.UP012.Profile.provider accepted
      "Generated.Known").mapError toString)
    let some types := plan.modules[0]? | throw (IO.userError "missing known artifact types")
    check s!"{fixture}: embeds exact known code"
      ((types.source.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}").length == 2)
    check s!"{fixture}: emits hash bound to code"
      ((types.source.splitOn s!"def scriptHashHex : String := {reprStr expectedHash}").length == 2)
    let emptyParameters := { accepted with parameters := some #[] }
    check s!"{fixture}: accepts explicit empty parameters"
      ((generate Workflow.Tests.UP012.Profile.provider emptyParameters "Generated.Empty").toOption.isSome)
    for unsupported in [
        { accepted with compiledCode := accepted.compiledCode ++ "00" },
        { accepted with compiledCode := "480100002221200101" },
        { accepted with parameters := some #[parameter] },
        { accepted with plutusVersion := "v2" },
        { accepted with handlers := #[] },
        { accepted with handlers := (target #[.spend, .mint]).handlers }] do
      match generate Workflow.Tests.UP012.Profile.provider unsupported "Generated.Unsupported" with
      | .error error => check s!"{fixture}: exact artifact and purpose guards" (error.kind == .unsupported)
      | .ok _ => throw (IO.userError s!"UP-012 accepted unsupported mutation of {fixture}")
  IO.println "UP-012 generator checks passed."

end Workflow.Tests.UP012.Tests

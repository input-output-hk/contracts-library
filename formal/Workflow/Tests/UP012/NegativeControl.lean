import Workflow
import Workflow.Tests.Support
import Workflow.Tests.UP012.Profile

namespace Workflow.Tests.UP012.NegativeControl

open Workflow.Tests.Support

private def propertyId := "UP-012-identity-control"

private def scope :=
  "TEST ONLY: retain the original signer instead of removing it; require rejection of the accepted context. The unchanged vesting model uses a 1,000,000-step bound."

private def retainSigner (text : String) (claimCount cancelCount : Nat) :
    Except Generator.Error String := do
  let mut result := text
  for (action, expected) in [("claim", claimCount), ("cancel", cancelCount)] do
    let original := s!"(signatoriesOf ({action} p)).tail"
    unless (result.splitOn original).length - 1 == expected do
      throw ⟨.unsupported, s!"identity control: unexpected {action} mutation count"⟩
    result := result.replace original s!"(signatoriesOf ({action} p))"
  return result

private def provider (legacyDeclarations : String) : Generator.Provider :=
  { id := propertyId
    generate := fun target modulePrefix => do
      let plan ← Profile.provider.generate target modulePrefix
      unless (plan.modules.filter (·.name == s!"{modulePrefix}.Checks")).size == 1 do
        throw ⟨.unsupported, "identity control: expected exactly one Checks module"⟩
      let modules ← plan.modules.mapM fun source => do
        if source.name != s!"{modulePrefix}.Checks" then return source
        let body ← retainSigner legacyDeclarations 3 3
        let header := (source.source.splitOn "theorem dropSigner_claim :").head?.getD ""
        return { source with source := s!"-- {scope}\n{header}{body}\nend {modulePrefix}\n" }
      let jobs ← plan.jobs.mapM fun job => do
        let counts ← match job.name with
          | "dropSigner_claim" => pure (2, 0)
          | "dropSigner_claim_applies" => pure (1, 0)
          | "dropSigner_cancel" => pure (0, 2)
          | "dropSigner_cancel_applies" => pure (0, 1)
          | _ => throw ⟨.unsupported, "identity control: unexpected obligation"⟩
        let some declaration := (legacyDeclarations.splitOn s!"theorem {job.name} :")[1]?
          | throw ⟨.unsupported, s!"identity control: missing legacy obligation {job.name}"⟩
        let statement := ((declaration.splitOn ":= by blaster").head?.getD "").trim
        let statement ← retainSigner statement counts.1 counts.2
        return { job with propertyId, statement, scope, binding := none }
      return { plan with
        modules
        jobs
        notes := #[scope]
        bindingsRequired := false
        propertyDefinition := none } }

def run : IO Unit := do
  startCase "UP012: retain-signer identity control"
    "FAIL/1; two property FAIL rows and two applicability PASS rows (intentional negative control)"
    "direct API: Generator.generate, Executor.run, Reporter.build" 300000
  let input ← IO.ofExcept ((← Input.read "Workflow/Tests/UP012/Inputs/plutus.json"
    "linear_vesting.linear_vesting").mapError toString)
  let legacy ← IO.FS.readFile "Workflow/Tests/UP012/Expected/legacy-declarations.lean.txt"
  let plan ← IO.ofExcept ((Generator.generate (provider legacy) input.target "Generated").mapError toString)
  let execution ← IO.ofExcept (← Executor.run plan {
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    outputRoot := some "output"
    budgetMs := 300000 })
  let report := Reporter.build plan execution
  let some directory := execution.directory
    | throw (IO.userError "identity control: missing output directory")
  IO.FS.writeFile (directory / "input.json") input.sourceText
  report.write directory
  IO.print report.text
  Workflow.Tests.Logging.line s!"Report: {directory / "report.json"}"
  showCompilerLogs directory
  check "identity control completes without execution problems"
    (execution.state == .completed && execution.problems.isEmpty)
  check "identity control produces FAIL/1" (report.status == .fail && report.exitCode == 1)
  check "identity control preserves all four obligations"
    (report.rows.map (·.job.name) ==
      #["dropSigner_claim", "dropSigner_claim_applies", "dropSigner_cancel", "dropSigner_cancel_applies"])
  check "identity control retains no official property definition" report.propertyDefinition.isNone
  for row in report.rows do
    check "identity control retains Valid expectations" (row.job.expected == .valid)
    check "identity control is labeled test-only" (row.job.propertyId == propertyId && row.job.scope == scope)
    check "identity control retains no official combined-check binding" row.job.binding.isNone
    let expectedModel := if row.job.name == "dropSigner_claim" || row.job.name == "dropSigner_claim_applies"
      then "TxM-007" else "TxM-008"
    check "identity control preserves the original transaction model" (row.job.txModelId == some expectedModel)
    if row.job.name.endsWith "_applies" then
      check s!"{row.job.name}: applicability remains Valid/PASS"
        (row.observed == some .valid && row.status == .pass)
    else
      check s!"{row.job.name}: unchanged signer produces Falsified/FAIL"
        (row.observed == some .falsified && row.status == .fail)
  let jsonRows ← rows report.toJson
  for row in jsonRows do
    check "identity control JSON does not claim an official combination"
      ((row.getObjVal? "combinedCheck").toOption == some .null)
  IO.println "UP012 identity negative control passed (the two property failures are intentional)."

end Workflow.Tests.UP012.NegativeControl

import Workflow
import Workflow.Tests.Support
import Workflow.Tests.UP015.Profile

namespace Workflow.Tests.UP015.NegativeControl

open Workflow.Tests.Support

private def propertyId := "UP-015-rejection-control"

private def scope :=
  "TEST ONLY: counterfactual rejection after reversing the two Claim outputs; retain the original validator, TxM-007, validity premises, nonidentity applicability, and 1,000,000-step bound."

private def counterfactual : String :=
  "∀ p,\n" ++
  "    validScriptContext (claim p) = true →\n" ++
  "    accepts ledgerFuel (claim p) →\n" ++
  "    validScriptContext (Formal.Properties.Universal.UP015.reverseOutputs (claim p)) = true →\n" ++
  "    rejects ledgerFuel (Formal.Properties.Universal.UP015.reverseOutputs (claim p))"

private def provider : Generator.Provider :=
  { id := propertyId
    generate := fun target modulePrefix => do
      let plan ← Profile.provider.generate target modulePrefix
      let marker := "theorem reverseOutputs_claim :"
      let terminator := "/-- A valid accepted Claim"
      let modules ← plan.modules.mapM fun source => do
        if source.name != s!"{modulePrefix}.Checks" then return source
        unless (source.source.splitOn marker).length == 2 &&
            (source.source.splitOn terminator).length == 2 do
          throw ⟨.unsupported, "rejection control: unexpected declaration layout"⟩
        let header := (source.source.splitOn marker).head!.replace
          "/-- Reversing the two Claim outputs preserves bounded acceptance. -/" ""
        let support := (source.source.splitOn terminator)[1]!
        return { source with source := s!"-- {scope}\n{header}{marker}\n    {counterfactual} := by\n  blaster\n\n{terminator}{support}" }
      return { plan with
        modules
        jobs := plan.jobs.map fun job =>
          { job with
            propertyId := propertyId
            scope := scope
            binding := none
            statement := if job.role == .property then counterfactual else job.statement }
        notes := #[scope]
        bindingsRequired := false
        propertyDefinition := none } }

def run : IO Unit := do
  startCase "UP015: counterfactual reversal-rejection control"
    "FAIL/1; property Falsified/FAIL and nonidentity applicability Valid/PASS"
    "direct API: Generator.generate, Executor.run, Reporter.build" 300000
  let input ← IO.ofExcept ((← Input.read "Workflow/Tests/UP012/Inputs/plutus.json"
    "linear_vesting.linear_vesting").mapError toString)
  let plan ← IO.ofExcept ((Generator.generate provider input.target "Generated").mapError toString)
  let execution ← IO.ofExcept (← Executor.run plan {
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    outputRoot := some "output"
    budgetMs := 300000 })
  let report := Reporter.build plan execution
  let some directory := execution.directory
    | throw (IO.userError "rejection control: missing output directory")
  IO.FS.writeFile (directory / "input.json") input.sourceText
  report.write directory
  IO.print report.text
  Workflow.Tests.Logging.line s!"Report: {directory / "report.json"}"
  showCompilerLogs directory
  check "rejection control completes without execution problems"
    (execution.state == .completed && execution.problems.isEmpty)
  check "rejection control produces FAIL/1" (report.status == .fail && report.exitCode == 1)
  check "rejection control preserves both original obligations"
    (report.rows.map (·.job.name) == #["reverseOutputs_claim", "reverseOutputs_claim_applies"])
  check "rejection control retains no official definition" report.propertyDefinition.isNone
  for row in report.rows do
    check "rejection control retains Valid expectations, original model, and test-only identity"
      (row.job.expected == .valid && row.job.txModelId == some "TxM-007" &&
       row.job.propertyId == propertyId && row.job.scope == scope && row.job.binding.isNone)
    if row.job.role == .applicability then
      check "actual-change applicability remains Valid/PASS"
        (row.observed == some .valid && row.status == .pass)
    else
      check "counterfactual reversal rejection is Falsified/FAIL"
        (row.observed == some .falsified && row.status == .fail)
  for row in ← rows report.toJson do
    check "rejection control JSON claims no official combined check"
      ((row.getObjVal? "combinedCheck").toOption == some .null)
  IO.println "UP015 rejection control passed (the property failure is intentional)."

end Workflow.Tests.UP015.NegativeControl

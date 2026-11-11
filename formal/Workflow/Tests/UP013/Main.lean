import Workflow.App.Run
import Workflow.Tests.UP013.ApplicabilityControl
import Workflow.Tests.UP013.NegativeControl

namespace Workflow.Tests.UP013

open Lean Workflow Workflow.Tests.Support

private def runApp (blueprint selector : String) (timeoutMs := 300000) : IO App.RunRecord := do
  let catalogue ← Fixture.catalogue
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "UP013 app scenarios receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  check "native UP013 catalogue supplies exactly the requested Claim and Cancel combinations"
    (catalogue.checks == Fixture.selection)
  let run ← App.Run.runWith catalogue.checks (fun id => pure (catalogue.loadCheck id))
    { path := blueprint, validators := #[selector], timeoutMs }
    { executorOptions := { leanPath }, outputRoot := "output" }
  IO.print run.text
  check "UP013 app completes without orchestration errors" (run.finished && run.exitCode == 0)
  check "UP013 saved app index matches the returned run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  check "UP013 app retains the exact shared input snapshot"
    ((← IO.FS.readFile (run.directory / "input.json")) == (← IO.FS.readFile blueprint))
  check "UP013 app retains one validator and both selected combinations"
    (run.validators.size == 1 && run.validators[0]!.name == selector &&
     run.validators[0]!.checks.map (·.id) == Fixture.selection)
  return run

private def resultDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  let some input := result.evidence.find? (·.fileName == some "input.json")
    | throw (IO.userError "UP013: missing retained check input")
  let some directory := input.parent | throw (IO.userError "UP013: missing check directory")
  check "saved UP013 assessment matches the returned result"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
  for reference in result.evidence do
    check "UP013 assessment evidence exists" (← reference.pathExists)
  return directory

private def passing : IO System.FilePath := do
  startCase "UP013: native Claim and Cancel unbounded-range rejection"
    "two PASS checks; Valid property and applicability obligations for each model"
    "Catalogue.loadCheck -> App.Run.runWith -> Engine.verifyOne" 300000
  let run ← runApp Fixture.blueprint Fixture.selector
  let catalogue ← Fixture.catalogue
  let mut directories : Array System.FilePath := #[]
  let mut generated : Array System.FilePath := #[]
  let mut obligationCount := 0
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP013: missing selected result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let context := if selected.id.modelId == "TxM-007" then "claim" else "cancel"
    let name := s!"unboundedRange_{context}"
    let applies := name ++ "_applies"
    let applicability : JobRef := { moduleName := "Generated.Checks", name := applies }
    let directory ← resultDirectory result
    directories := directories.push directory
    IO.println s!"CheckResult: {directory / "check-result.json"}"
    showCompilerLogs directory
    check "UP013 native result retains exact property, model, and limitations"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding &&
       result.check.propertyDefinition.id? == some "UP-013" &&
       result.check.propertyDefinition.version? == some 1 &&
       result.check.propertyDefinition.primary? == some "Formal.Properties.Universal.UP013.statement")
    obligationCount := obligationCount + result.obligations.size
    check "UP013 native check is PASS with exactly two Valid obligations"
      (result.status == .pass && result.notRun.isNone && !result.timedOut &&
       selected.displayStatus == "PASS" &&
       result.obligations.map (·.job.name) == #[name, applies] && result.obligations.all fun row =>
        row.status == .pass && row.observed == some .valid && row.evidenceComplete &&
        row.job.expected == .valid && row.job.moduleName == "Generated.Checks" &&
        row.job.propertyId == "UP-013" && row.job.txModelId == some selected.id.modelId &&
        (row.job.scope.splitOn "1,000,000 CEK steps").length > 1 &&
        row.job.binding == some configured.context.binding)
    check "UP013 retains the main statement, applicability statement, and exact support link"
      (result.obligations.all fun row =>
        if row.job.name == name then
          row.job.role == .property && row.job.applicability == some applicability &&
          row.job.statement == s!"Formal.Properties.Universal.UP013.statement validScriptContext (accepts 1000000) (rejects 1000000) {context}"
        else
          row.job.role == .applicability && row.job.applicability.isNone &&
          row.job.statement == s!"Formal.Properties.Universal.UP013.applicability validScriptContext (accepts 1000000) {context}")
    check "UP013 check retains the exact captured input"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile Fixture.blueprint))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let jobs ← IO.ofExcept do (← manifest.getObjVal? "jobs").getArr?
    check "UP013 execution retains its exact native definition and obligation binding"
      ((manifest.getObjVal? "propertyDefinition").toOption ==
        some configured.context.propertyDefinition.toJson && jobs.size == 2 && jobs.all fun job =>
        (job.getObjVal? "property").toOption == some (.str "UP-013") &&
        (job.getObjVal? "txModelId").toOption == some (.str selected.id.modelId) &&
        (job.getObjVal? "transactionModel").toOption == some configured.context.binding.txModel.toJson &&
        (job.getObjVal? "combinedCheck").toOption == some configured.context.binding.combinedCheck.toJson &&
        (job.getObjVal? "observed").toOption == some (.str "valid"))
    for row in result.obligations do
      let matching := jobs.filter fun job =>
        (job.getObjVal? "name").toOption == some (.str row.job.name)
      let support := row.job.applicability.map (fun reference => Json.mkObj [
        ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null
      check "UP013 execution retains each exact statement, role, and applicability link"
        (matching.size == 1 && matching.all fun job =>
          (job.getObjVal? "module").toOption == some (.str row.job.moduleName) &&
          (job.getObjVal? "statement").toOption == some (.str row.job.statement) &&
          (job.getObjVal? "role").toOption == some (.str row.job.role.label) &&
          (job.getObjVal? "applicability").toOption == some support)
    let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
    check "UP013 check executes exactly three generated modules" (modules.size == 3)
    for name in #["Types", "Tx", "Checks"] do
      let source := directory / "Generated" / s!"{name}.lean"
      generated := generated.push source
      check s!"UP013 retains generated {name} source and compiler logs"
        ((← source.pathExists) && (← (source.withExtension "stdout.log").pathExists) &&
         (← (source.withExtension "stderr.log").pathExists))
  check "UP013 retains four obligations, two check directories, and six generated source files"
    (obligationCount == 4 && directories.size == 2 && directories[0]! != directories[1]! && generated.size == 6 &&
     generated.toList.eraseDups.length == 6)
  check "UP013 app publishes the shared source index" (run.sourceIndex == some "sources/index.json")
  let index ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "sources/index.json")))
  let sources ← IO.ofExcept do (← index.getObjVal? "sources").getArr?
  let modules ← sources.mapM fun source => stringField source "module"
  check "UP013 shared project snapshots are unique" (modules.toList.eraseDups.length == modules.size)
  for name in #["Formal.TxModels.Definitions.TxM007", "Formal.TxModels.Definitions.TxM008",
      "Formal.Properties.Universal.UP013.Definition", "Formal.Properties.Universal.UP013.Run"] do
    check s!"UP013 source index retains {name} exactly once" ((modules.filter (· == name)).size == 1)
  for source in sources do
    let name ← stringField source "module"
    let snapshot := run.directory / (← stringField source "source")
    check "UP013 shared source snapshots compile successfully and retain their compiled files"
      ((← stringField source "state") == "compiled" &&
       (← (run.directory / (← stringField source "compiled")).pathExists))
    check "UP013 source snapshots match the project sources used by the run"
      ((← IO.FS.readFile snapshot) == (← IO.FS.readFile (name.replace "." "/" ++ ".lean")))
  return run.directory

private def notRun (blueprint selector : String) (reason : Assessor.NotRunReason) :
    IO System.FilePath := do
  startCase s!"UP013: {reason.label} target"
    "two SKIPPED checks; no obligations, generated modules, or solver execution"
    "Catalogue.loadCheck -> App.Run.runWith -> admission or property skip" 300000
  let run ← runApp blueprint selector
  let catalogue ← Fixture.catalogue
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP013: missing skipped result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let directory ← resultDirectory result
    check "UP013 non-execution retains the exact reason without a passing observation"
      (result.status == .inconclusive && result.notRun == some reason &&
       selected.notRunReason == some reason && selected.displayStatus == "SKIPPED" &&
       result.obligations.isEmpty && !result.reasons.isEmpty && !result.timedOut)
    check "UP013 non-execution retains the selected official property and model binding"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding)
    check "UP013 non-execution retains input without creating execution artifacts"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile blueprint) &&
       !(← (directory / "execution.json").pathExists) &&
       !(← (directory / "Generated").pathExists) &&
       !result.evidence.any (fun path => path.toString.endsWith ".lean"))
  check "UP013 non-execution creates no shared source bundle"
    (run.sourceIndex.isNone && !(← (run.directory / "sources").pathExists))
  return run.directory

def run : IO Unit := do
  ApplicabilityControl.unit
  NegativeControl.unit
  let passed ← passing
  let unsupported ← notRun "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault" .unsupported
  let skipped ← notRun "Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json"
    Fixture.selector .notApplicable
  check "UP013 passing, unsupported, and artifact-skip runs retain separate evidence"
    ([passed, unsupported, skipped].eraseDups.length == 3)
  NegativeControl.run
  IO.println "UP013 whole-workflow checks passed."

end Workflow.Tests.UP013

def main (args : List String) : IO Unit := do
  if args == ["--unit"] then
    Workflow.Tests.UP013.ApplicabilityControl.unit
    Workflow.Tests.UP013.NegativeControl.unit
  else if args.isEmpty then Workflow.Tests.UP013.run
  else throw (IO.userError "Usage: workflow_up013_tests [--unit]")

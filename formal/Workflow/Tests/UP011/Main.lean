import Workflow.App.Run
import Workflow.Tests.UP011.ApplicabilityControl
import Workflow.Tests.UP011.NegativeControl

namespace Workflow.Tests.UP011

open Lean Workflow Workflow.Tests.Support

private def runApp (blueprint selector : String) (timeoutMs := 300000) : IO App.RunRecord := do
  let catalogue ← Fixture.catalogue
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "UP011 app scenarios receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  check "native UP011 catalogue supplies exactly the requested Claim combination"
    (catalogue.checks == Fixture.selection)
  let run ← App.Run.runWith catalogue.checks (fun id => pure (catalogue.loadCheck id))
    { path := blueprint, validators := #[selector], timeoutMs }
    { executorOptions := { leanPath }, outputRoot := "output" }
  IO.print run.text
  check "UP011 app completes without orchestration errors" (run.finished && run.exitCode == 0)
  check "UP011 saved app index matches the returned run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  check "UP011 app retains the exact shared input snapshot"
    ((← IO.FS.readFile (run.directory / "input.json")) == (← IO.FS.readFile blueprint))
  check "UP011 app retains one validator and the selected Claim combination"
    (run.validators.size == 1 && run.validators[0]!.name == selector &&
     run.validators[0]!.checks.map (·.id) == Fixture.selection)
  return run

private def resultDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  let some input := result.evidence.find? (·.fileName == some "input.json")
    | throw (IO.userError "UP011: missing retained check input")
  let some directory := input.parent | throw (IO.userError "UP011: missing check directory")
  check "saved UP011 assessment matches the returned result"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
  for reference in result.evidence do
    check "UP011 assessment evidence exists" (← reference.pathExists)
  return directory

private def passing : IO System.FilePath := do
  startCase "UP011: native Claim continuation-payment-credential rejection"
    "one PASS check; Valid property and applicability obligations for Claim"
    "Catalogue.loadCheck -> App.Run.runWith -> Engine.verifyOne" 300000
  let run ← runApp Fixture.blueprint Fixture.selector
  let catalogue ← Fixture.catalogue
  let mut directories : Array System.FilePath := #[]
  let mut generated : Array System.FilePath := #[]
  let mut obligationCount := 0
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP011: missing selected result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let context := "claim"
    let name := s!"continuationElsewhere_{context}"
    let applies := name ++ "_applies"
    let applicability : JobRef := { moduleName := "Generated.Checks", name := applies }
    let directory ← resultDirectory result
    directories := directories.push directory
    IO.println s!"CheckResult: {directory / "check-result.json"}"
    showCompilerLogs directory
    check "UP011 native result retains exact property, model, and limitations"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding &&
       result.check.propertyDefinition.id? == some "UP-011" &&
       result.check.propertyDefinition.version? == some 1 &&
       result.check.propertyDefinition.primary? == some "Formal.Properties.Universal.UP011.statement")
    obligationCount := obligationCount + result.obligations.size
    check "UP011 native check is PASS with exactly two Valid obligations"
      (result.status == .pass && result.notRun.isNone && !result.timedOut &&
       selected.displayStatus == "PASS" &&
       result.obligations.map (·.job.name) == #[name, applies] && result.obligations.all fun row =>
        row.status == .pass && row.observed == some .valid && row.evidenceComplete &&
        row.job.expected == .valid && row.job.moduleName == "Generated.Checks" &&
        row.job.propertyId == "UP-011" && row.job.txModelId == some selected.id.modelId &&
        (row.job.scope.splitOn "1,000,000 CEK steps").length > 1 &&
        row.job.binding == some configured.context.binding)
    check "UP011 retains the main statement, applicability statement, and exact support link"
      (result.obligations.all fun row =>
        if row.job.name == name then
          row.job.role == .property && row.job.applicability == some applicability &&
          row.job.statement == s!"Formal.Properties.Universal.UP011.statement validScriptContext (accepts 1000000) (rejects 1000000) {context}"
        else
          row.job.role == .applicability && row.job.applicability.isNone &&
          row.job.statement == s!"Formal.Properties.Universal.UP011.applicability validScriptContext (accepts 1000000) (rejects 1000000) {context}")
    check "UP011 check retains the exact captured input"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile Fixture.blueprint))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let jobs ← IO.ofExcept do (← manifest.getObjVal? "jobs").getArr?
    check "UP011 execution retains its exact native definition and obligation binding"
      ((manifest.getObjVal? "propertyDefinition").toOption ==
        some configured.context.propertyDefinition.toJson && jobs.size == 2 && jobs.all fun job =>
        (job.getObjVal? "property").toOption == some (.str "UP-011") &&
        (job.getObjVal? "txModelId").toOption == some (.str selected.id.modelId) &&
        (job.getObjVal? "transactionModel").toOption == some configured.context.binding.txModel.toJson &&
        (job.getObjVal? "combinedCheck").toOption == some configured.context.binding.combinedCheck.toJson &&
        (job.getObjVal? "observed").toOption == some (.str "valid"))
    for row in result.obligations do
      let matching := jobs.filter fun job =>
        (job.getObjVal? "name").toOption == some (.str row.job.name)
      let support := row.job.applicability.map (fun reference => Json.mkObj [
        ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null
      check "UP011 execution retains each exact statement, role, and applicability link"
        (matching.size == 1 && matching.all fun job =>
          (job.getObjVal? "module").toOption == some (.str row.job.moduleName) &&
          (job.getObjVal? "statement").toOption == some (.str row.job.statement) &&
          (job.getObjVal? "role").toOption == some (.str row.job.role.label) &&
          (job.getObjVal? "applicability").toOption == some support)
    let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
    check "UP011 check executes exactly three generated modules" (modules.size == 3)
    for name in #["Types", "Tx", "Checks"] do
      let source := directory / "Generated" / s!"{name}.lean"
      generated := generated.push source
      check s!"UP011 retains generated {name} source and compiler logs"
        ((← source.pathExists) && (← (source.withExtension "stdout.log").pathExists) &&
         (← (source.withExtension "stderr.log").pathExists))
  check "UP011 retains two obligations, one check directory, and three generated source files"
    (obligationCount == 2 && directories.size == 1 && generated.size == 3 &&
     generated.toList.eraseDups.length == 3)
  check "UP011 app publishes the shared source index" (run.sourceIndex == some "sources/index.json")
  let index ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "sources/index.json")))
  let sources ← IO.ofExcept do (← index.getObjVal? "sources").getArr?
  let modules ← sources.mapM fun source => stringField source "module"
  check "UP011 shared project snapshots are unique" (modules.toList.eraseDups.length == modules.size)
  check "UP011 Claim execution does not prepare the Cancel model"
    (!modules.contains "Formal.TxModels.Definitions.TxM008")
  for name in #["Formal.TxModels.Definitions.TxM007",
      "Formal.Properties.Universal.UP011.Definition", "Formal.Properties.Universal.UP011.Run"] do
    check s!"UP011 source index retains {name} exactly once" ((modules.filter (· == name)).size == 1)
  for source in sources do
    let name ← stringField source "module"
    let snapshot := run.directory / (← stringField source "source")
    check "UP011 shared source snapshots compile successfully and retain their compiled files"
      ((← stringField source "state") == "compiled" &&
       (← (run.directory / (← stringField source "compiled")).pathExists))
    check "UP011 source snapshots match the project sources used by the run"
      ((← IO.FS.readFile snapshot) == (← IO.FS.readFile (name.replace "." "/" ++ ".lean")))
  return run.directory

private def notRun (blueprint selector : String) (reason : Assessor.NotRunReason) :
    IO System.FilePath := do
  startCase s!"UP011: {reason.label} target"
    "one SKIPPED check; no obligations, generated modules, or solver execution"
    "Catalogue.loadCheck -> App.Run.runWith -> admission or property skip" 300000
  let run ← runApp blueprint selector
  let catalogue ← Fixture.catalogue
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP011: missing skipped result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let directory ← resultDirectory result
    check "UP011 non-execution retains the exact reason without a passing observation"
      (result.status == .inconclusive && result.notRun == some reason &&
       selected.notRunReason == some reason && selected.displayStatus == "SKIPPED" &&
       result.obligations.isEmpty && !result.reasons.isEmpty && !result.timedOut)
    check "UP011 non-execution retains the selected official property and model binding"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding)
    check "UP011 non-execution retains input without creating execution artifacts"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile blueprint) &&
       !(← (directory / "execution.json").pathExists) &&
       !(← (directory / "Generated").pathExists) &&
       !result.evidence.any (fun path => path.toString.endsWith ".lean"))
  check "UP011 non-execution creates no shared source bundle"
    (run.sourceIndex.isNone && !(← (run.directory / "sources").pathExists))
  return run.directory

private def selection : IO Unit := do
  let catalogue ← Fixture.catalogue
  let requested ← IO.ofExcept (App.parseRequest [Fixture.blueprint, Fixture.selector, "--check", "UP-011"])
  for (request, source) in #[
      (requested, none),
      ({ requested with properties := #[] }, none),
      ({ requested with properties := #[], checksFile := some "checks.json" },
        some "{\"UP-011\": true}")] do
    let selected ← IO.ofExcept (App.selectChecks request catalogue.checks source)
    check "UP011 CLI selection derives only the enabled Claim pairing"
      (selected == Fixture.selection && selected.size == 1 &&
       selected.all (·.modelId == "TxM-007"))
  IO.println "UP011 Claim-only CLI selection checks passed."

private def unit : IO Unit := do
  selection
  ApplicabilityControl.unit
  NegativeControl.unit

def run : IO Unit := do
  unit
  let passed ← passing
  let unsupported ← notRun "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault" .unsupported
  let skipped ← notRun "Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json"
    Fixture.selector .notApplicable
  check "UP011 passing, unsupported, and artifact-skip runs retain separate evidence"
    ([passed, unsupported, skipped].eraseDups.length == 3)
  NegativeControl.run
  IO.println "UP011 whole-workflow checks passed."

end Workflow.Tests.UP011

def main (args : List String) : IO Unit := do
  if args == ["--unit"] then
    Workflow.Tests.UP011.unit
  else if args == ["--negative-control"] then Workflow.Tests.UP011.NegativeControl.run
  else if args.isEmpty then Workflow.Tests.UP011.run
  else throw (IO.userError "Usage: workflow_up011_tests [--unit | --negative-control]")

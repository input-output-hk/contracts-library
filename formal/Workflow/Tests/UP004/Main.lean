import Workflow.App.Run
import Workflow.Tests.UP004.NegativeControl

namespace Workflow.Tests.UP004

open Lean Workflow Workflow.Tests.Support

private def runApp (blueprint selector : String) (timeoutMs := 300000) : IO App.RunRecord := do
  let catalogue ← Fixture.catalogue
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "UP004 app scenarios receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  check "native UP004 catalogue supplies exactly the requested Claim and Cancel combinations"
    (catalogue.checks == Fixture.selection)
  let run ← App.Run.runWith catalogue.checks (fun id => pure (catalogue.loadCheck id))
    { path := blueprint, validators := #[selector], timeoutMs }
    { executorOptions := { leanPath }, outputRoot := "output" }
  IO.print run.text
  check "UP004 app completes without orchestration errors" (run.finished && run.exitCode == 0)
  check "UP004 saved app index matches the returned run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  check "UP004 app retains the exact shared input snapshot"
    ((← IO.FS.readFile (run.directory / "input.json")) == (← IO.FS.readFile blueprint))
  check "UP004 app retains one validator and both selected combinations"
    (run.validators.size == 1 && run.validators[0]!.name == selector &&
     run.validators[0]!.checks.map (·.id) == Fixture.selection)
  return run

private def resultDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  let some input := result.evidence.find? (·.fileName == some "input.json")
    | throw (IO.userError "UP004: missing retained check input")
  let some directory := input.parent | throw (IO.userError "UP004: missing check directory")
  check "saved UP004 assessment matches the returned result"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
  for reference in result.evidence do
    check "UP004 assessment evidence exists" (← reference.pathExists)
  return directory

private def passing : IO System.FilePath := do
  startCase "UP004: native Claim and Cancel rejection existence"
    "two PASS checks; one Valid property obligation per check"
    "Catalogue.loadCheck -> App.Run.runWith -> Engine.verifyOne" 300000
  let run ← runApp Fixture.blueprint Fixture.selector
  let catalogue ← Fixture.catalogue
  let mut directories : Array System.FilePath := #[]
  let mut generated : Array System.FilePath := #[]
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP004: missing selected result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let context := if selected.id.modelId == "TxM-007" then "claim" else "cancel"
    let name := s!"someRejected_{context}"
    let directory ← resultDirectory result
    directories := directories.push directory
    IO.println s!"CheckResult: {directory / "check-result.json"}"
    showCompilerLogs directory
    check "UP004 native result retains exact property, model, and limitations"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding &&
       result.check.propertyDefinition.id? == some "UP-004" &&
       result.check.propertyDefinition.version? == some 1 &&
       result.check.propertyDefinition.primary? == some "Formal.Properties.Universal.UP004.statement")
    check "UP004 native existence check is PASS with exactly one Valid obligation"
      (result.status == .pass && result.notRun.isNone && !result.timedOut &&
       result.obligations.map (·.job.name) == #[name] && result.obligations.all fun row =>
        row.status == .pass && row.observed == some .valid && row.evidenceComplete &&
        row.job.expected == .valid && row.job.role == .property && row.job.applicability.isNone &&
        row.job.propertyId == "UP-004" && row.job.txModelId == some selected.id.modelId &&
        row.job.statement == s!"Formal.Properties.Universal.UP004.statement validScriptContext (rejects 1000000) {context}" &&
        (row.job.scope.splitOn "1,000,000 CEK steps").length > 1 &&
        row.job.binding == some configured.context.binding)
    check "UP004 check retains the exact captured input"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile Fixture.blueprint))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let jobs ← IO.ofExcept do (← manifest.getObjVal? "jobs").getArr?
    check "UP004 execution retains its exact native definition and obligation binding"
      ((manifest.getObjVal? "propertyDefinition").toOption ==
        some configured.context.propertyDefinition.toJson && jobs.size == 1 && jobs.all fun job =>
        (job.getObjVal? "name").toOption == some (.str name) &&
        (job.getObjVal? "property").toOption == some (.str "UP-004") &&
        (job.getObjVal? "txModelId").toOption == some (.str selected.id.modelId) &&
        (job.getObjVal? "transactionModel").toOption == some configured.context.binding.txModel.toJson &&
        (job.getObjVal? "combinedCheck").toOption == some configured.context.binding.combinedCheck.toJson &&
        (job.getObjVal? "applicability").toOption == some .null &&
        (job.getObjVal? "observed").toOption == some (.str "valid"))
    let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
    check "UP004 check executes exactly three generated modules" (modules.size == 3)
    for name in #["Types", "Tx", "Checks"] do
      let source := directory / "Generated" / s!"{name}.lean"
      generated := generated.push source
      check s!"UP004 retains generated {name} source and compiler logs"
        ((← source.pathExists) && (← (source.withExtension "stdout.log").pathExists) &&
         (← (source.withExtension "stderr.log").pathExists))
  check "UP004 retains two separate check directories and six generated source files"
    (directories.size == 2 && directories[0]! != directories[1]! && generated.size == 6 &&
     generated.toList.eraseDups.length == 6)
  check "UP004 app publishes the shared source index" (run.sourceIndex == some "sources/index.json")
  let index ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "sources/index.json")))
  let sources ← IO.ofExcept do (← index.getObjVal? "sources").getArr?
  let modules ← sources.mapM fun source => stringField source "module"
  check "UP004 shared project snapshots are unique" (modules.toList.eraseDups.length == modules.size)
  for name in #["Formal.TxModels.Definitions.TxM007", "Formal.TxModels.Definitions.TxM008",
      "Formal.Properties.Universal.UP004.Definition", "Formal.Properties.Universal.UP004.Run"] do
    check s!"UP004 source index retains {name} exactly once" ((modules.filter (· == name)).size == 1)
  for source in sources do
    let name ← stringField source "module"
    let snapshot := run.directory / (← stringField source "source")
    check "UP004 shared source snapshots compile successfully and retain their compiled files"
      ((← stringField source "state") == "compiled" &&
       (← (run.directory / (← stringField source "compiled")).pathExists))
    check "UP004 source snapshots match the project sources used by the run"
      ((← IO.FS.readFile snapshot) == (← IO.FS.readFile (name.replace "." "/" ++ ".lean")))
  return run.directory

private def notRun (blueprint selector : String) (reason : Assessor.NotRunReason) :
    IO System.FilePath := do
  startCase s!"UP004: {reason.label} target"
    "two SKIPPED checks; no obligations, generated modules, or solver execution"
    "Catalogue.loadCheck -> App.Run.runWith -> admission or property skip" 300000
  let run ← runApp blueprint selector
  let catalogue ← Fixture.catalogue
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP004: missing skipped result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let directory ← resultDirectory result
    check "UP004 non-execution retains the exact reason without a passing observation"
      (result.status == .inconclusive && result.notRun == some reason &&
       selected.notRunReason == some reason && selected.displayStatus == "SKIPPED" &&
       result.obligations.isEmpty && !result.reasons.isEmpty && !result.timedOut)
    check "UP004 non-execution retains the selected official property and model binding"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding)
    check "UP004 non-execution retains input without creating execution artifacts"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile blueprint) &&
       !(← (directory / "execution.json").pathExists) &&
       !(← (directory / "Generated").pathExists) &&
       !result.evidence.any (fun path => path.toString.endsWith ".lean"))
  check "UP004 non-execution creates no shared source bundle"
    (run.sourceIndex.isNone && !(← (run.directory / "sources").pathExists))
  return run.directory

private def timedOut : IO System.FilePath := do
  startCase "UP004: native checks exceed the execution deadline"
    "two TIMEOUT checks; rejection existence remains INCONCLUSIVE"
    "Catalogue.loadCheck -> App.Run.runWith -> execution deadline" 1
  let run ← runApp Fixture.blueprint Fixture.selector 1
  let catalogue ← Fixture.catalogue
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "UP004: missing timed-out result")
    let configured ← IO.ofExcept (catalogue.loadCheck selected.id)
    let directory ← resultDirectory result
    IO.println s!"CheckResult: {directory / "check-result.json"}"
    showCompilerLogs directory
    check "UP004 timeout is unresolved, with no passing or skipped result"
      (result.status == .inconclusive && result.timedOut && result.notRun.isNone &&
       selected.timedOut && selected.notRunReason.isNone && selected.displayStatus == "TIMEOUT" &&
       !result.reasons.isEmpty && result.obligations.size == 1 &&
       result.obligations.all fun row => row.status == .inconclusive &&
        row.observed == some .inconclusive && !row.evidenceComplete &&
        row.job.expected == .valid && row.job.applicability.isNone)
    check "UP004 timeout retains the selected native definition and model binding"
      (result.check.propertyDefinition == configured.context.propertyDefinition &&
       result.check.binding == configured.context.binding &&
       result.obligations.all fun row => row.job.binding == some configured.context.binding)
    check "UP004 timeout retains its original input"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile Fixture.blueprint))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    check "UP004 execution manifest records the original deadline and timeout"
      ((manifest.getObjVal? "state").toOption == some (.str "timedOut") &&
       (manifest.getObjVal? "budgetMs").toOption == some (Lean.toJson (1 : Nat)))
    for name in #["Types", "Tx", "Checks"] do
      check s!"UP004 timeout retains generated {name} source"
        (← (directory / "Generated" / s!"{name}.lean").pathExists)
    let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
    check "UP004 timeout records the module interrupted by the deadline"
      (!modules.isEmpty && modules.any fun item =>
        (item.getObjVal? "timedOut").toOption == some (.bool true))
    for item in modules do
      let path := System.FilePath.mk (← stringField item "path")
      check "UP004 timeout retains logs for recorded module attempts"
        ((← (path.withExtension "stdout.log").pathExists) &&
         (← (path.withExtension "stderr.log").pathExists))
  return run.directory

def run : IO Unit := do
  NegativeControl.unit
  let passed ← passing
  let unsupported ← notRun "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault" .unsupported
  let skipped ← notRun "Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json"
    Fixture.selector .notApplicable
  let timeout ← timedOut
  check "UP004 passing, unsupported, artifact-skip, and timeout runs retain separate evidence"
    ([passed, unsupported, skipped, timeout].eraseDups.length == 4)
  NegativeControl.run
  IO.println "UP004 whole-workflow checks passed."

end Workflow.Tests.UP004

def main (args : List String) : IO Unit := do
  if args == ["--unit"] then Workflow.Tests.UP004.NegativeControl.unit
  else if args.isEmpty then Workflow.Tests.UP004.run
  else throw (IO.userError "Usage: workflow_up004_tests [--unit]")

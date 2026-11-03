import Workflow.App.Run
import Workflow.Tests.UP015.Tests
import Workflow.Tests.UP015.NegativeControl

namespace Workflow.Tests.UP015

open Lean Workflow Workflow.Tests.Support

private def selection : Array CheckId := #[
  { propertyId := "UP-012", definitionVersion := 1, modelId := "TxM-007" },
  { propertyId := "UP-015", definitionVersion := 1, modelId := "TxM-007" }]

private def runApp (blueprint selector : String) (ids : Array CheckId) : IO App.RunRecord := do
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "app scenarios receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  let run ← App.Run.runWith ids
    (fun id => Candidates.Catalogue.loadCheck id.propertyId id.definitionVersion id.modelId)
    { path := blueprint, validators := #[selector], timeoutMs := 300000 }
    { executorOptions := { leanPath }, outputRoot := "output" }
  IO.print run.text
  check "app run completes and retains its selected checks" (run.finished && run.exitCode == 0)
  check "app index matches the returned run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  check "app retains the exact shared input snapshot"
    ((← IO.FS.readFile (run.directory / "input.json")) == (← IO.FS.readFile blueprint))
  check "app selection contains one validator and the requested combinations"
    (run.validators.size == 1 && run.validators[0]!.name == selector &&
     run.validators[0]!.checks.map (·.id) == ids)
  return run

private def resultDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  let some input := result.evidence.find? (·.fileName == some "input.json")
    | throw (IO.userError "missing retained check input")
  let some directory := input.parent | throw (IO.userError "missing check directory")
  check "saved assessment matches returned check result"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
  for reference in result.evidence do
    check "assessment evidence exists" (← reference.pathExists)
  return directory

private def passing : IO System.FilePath := do
  startCase "UP015: UP012 and UP015 on the same pinned Claim model"
    "two PASS checks; two Valid obligations per check"
    "App.Run.runWith -> loadCheck -> Engine.verifyOne" 300000
  let blueprint := "Workflow/Tests/UP012/Inputs/plutus.json"
  let run ← runApp blueprint "linear_vesting.linear_vesting" selection
  let mut directories : Array System.FilePath := #[]
  for selected in run.validators[0]!.checks do
    let some result := selected.result | throw (IO.userError "missing selected result")
    let configured ← IO.ofExcept (← Candidates.Catalogue.loadCheck
      selected.id.propertyId selected.id.definitionVersion selected.id.modelId)
    let names := if selected.id.propertyId == "UP-012" then
      #["dropSigner_claim", "dropSigner_claim_applies"]
      else #["reverseOutputs_claim", "reverseOutputs_claim_applies"]
    let directory ← resultDirectory result
    directories := directories.push directory
    IO.println s!"CheckResult: {directory / "check-result.json"}"
    IO.println s!"Status: {result.status.label}; obligations: {result.obligations.size}"
    showCompilerLogs directory
    check "both selected checks satisfy the independent PASS expectation"
      (result.status == .pass && result.obligations.map (·.job.name) == names)
    check "both obligations retain Valid observations and exact official bindings"
      (result.obligations.all fun row =>
        row.status == .pass && row.observed == some .valid && row.evidenceComplete &&
        row.job.expected == .valid && row.job.txModelId == some "TxM-007" &&
        row.job.binding == some configured.context.binding)
    check "each check retains the same captured input"
      ((← IO.FS.readFile (directory / "input.json")) == (← IO.FS.readFile blueprint))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
    check "each selected check executes exactly three generated modules" (modules.size == 3)
    for name in #["Types", "Tx", "Checks"] do
      let source := directory / "Generated" / s!"{name}.lean"
      check s!"retains generated {name} source and compiler logs"
        ((← source.pathExists) && (← (source.withExtension "stdout.log").pathExists) &&
         (← (source.withExtension "stderr.log").pathExists))
  check "selected checks have separate retained evidence directories"
    (directories.size == 2 && directories[0]! != directories[1]!)
  check "app publishes one shared source index" (run.sourceIndex == some "sources/index.json")
  let index ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "sources/index.json")))
  let sources ← IO.ofExcept do (← index.getObjVal? "sources").getArr?
  let modules ← sources.mapM fun source => stringField source "module"
  check "all project snapshots are shared exactly once"
    (modules.toList.eraseDups.length == modules.size)
  for name in #["Formal.TxModels.Definitions.TxM007", "Formal.Properties.Universal.UP012.Definition",
      "Formal.Properties.Universal.UP015.Definition"] do
    check s!"shared snapshot retains {name} once" ((modules.filter (· == name)).size == 1)
  for source in sources do
    check "shared source snapshots compiled successfully" ((← stringField source "state") == "compiled")
    check "shared source and compiled snapshot files exist"
      ((← (run.directory / (← stringField source "source")).pathExists) &&
       (← (run.directory / (← stringField source "compiled")).pathExists))
  return run.directory

private def unsupported : IO System.FilePath := do
  startCase "UP015: unsupported artifact"
    "INCONCLUSIVE; no generated modules or solver execution"
    "App.Run.runWith -> pinned-profile rejection" 300000
  let id : CheckId := { propertyId := "UP-015", definitionVersion := 1, modelId := "TxM-007" }
  let run ← runApp "Workflow/Tests/UP012/Inputs/unsupported.json" "unsupported.validator" #[id]
  let some result := run.validators[0]!.checks[0]!.result
    | throw (IO.userError "missing unsupported result")
  let directory ← resultDirectory result
  check "unsupported artifact remains inconclusive without proof observations"
    (result.status == .inconclusive && result.obligations.isEmpty && !result.reasons.isEmpty)
  check "unsupported artifact retains the selected property identity"
    (result.check.propertyDefinition.id? == some "UP-015" &&
     result.check.propertyDefinition.version? == some 1)
  check "unsupported artifact executes no modules and creates no source bundle"
    (!(← (directory / "execution.json").pathExists) &&
     !(← (directory / "Generated").pathExists) && run.sourceIndex.isNone)
  return run.directory

def run : IO Unit := do
  Tests.run
  let successful ← passing
  let rejected ← unsupported
  check "passing and unsupported runs retain separate evidence" (successful != rejected)
  NegativeControl.run
  IO.println "UP015 whole-workflow checks passed."

end Workflow.Tests.UP015

def main (args : List String) : IO Unit := do
  if args == ["--unit"] then Workflow.Tests.UP015.Tests.run
  else if args.isEmpty then Workflow.Tests.UP015.run
  else throw (IO.userError "Usage: workflow-up015-tests [--unit]")

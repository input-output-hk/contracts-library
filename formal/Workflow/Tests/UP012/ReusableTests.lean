import Workflow.App.Run
import Workflow.Tests.Support
import Candidates.Catalogue

namespace Workflow.Tests.UP012.ReusableTests

open Lean Workflow Workflow.Generator Workflow.Tests.Support

private def fixture := "Workflow/Tests/UP012/Inputs/reusable.json"
private def targets := #["controller_gate.controller_gate", "missing_signature.missing_signature", "never_accept.never_accept"]
private def hashes := #["29f04fa6e54c2c0cb02b8ce6bc044dd22f7dae9e3196f1cb7b7c1b0f",
  "835a85204b6fb6abf0f409583fa5b5753f270937a7ce53d2fd8f56c9",
  "eaef4b02e2a6b394858ca3d4c69e47123e9e1ecb0ea69a050069aacf"]
private def names := #["dropSigner_spend", "dropSigner_spend_applies"]

private def source (plan : GenerationPlan) (suffix : String) : IO String := do
  let some result := plan.modules.find? (·.name.endsWith suffix)
    | throw (IO.userError s!"missing generated {suffix}")
  return result.source

private partial def relabel : Json → Json
  | .obj fields => Json.mkObj (fields.toList.map fun (key, value) =>
      (key, if key == "title" || key == "description" then .str "arbitrary label" else relabel value))
  | .arr values => .arr (values.map relabel)
  | other => other

def runUnit : IO Unit := do
  let configured ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 "TxM-009")
  for index in [:targets.size] do
    let target := (← IO.ofExcept ((← Input.read fixture targets[index]!).mapError toString)).target
    let plan ← IO.ofExcept ((generateOne configured target "Generated.Reusable").mapError toString)
    check "new programs receive both selected obligations"
      (plan.jobs.map (·.name) == names && plan.modules.size == 3 &&
       plan.jobs.all (fun job => job.expected == .valid && job.binding == some configured.context.binding))
    let types ← source plan ".Types"
    check "new programs retain exact code and independently pinned script hashes"
      ((types.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr target.compiledCode}").length == 2 &&
       (types.splitOn s!"def scriptHashHex : String := {reprStr hashes[index]!}").length == 2)
    let renamed := { target with
      name := "anything", definitions := target.definitions.map relabel
      handlers := target.handlers.map fun handler => { handler with
        name := "arbitrary.spend"
        datum := handler.datum.map fun argument => { argument with title := some "not owner", schema := relabel argument.schema },
        redeemer := handler.redeemer.map fun argument => { argument with title := some "anything", schema := relabel argument.schema } } }
    let renamedPlan ← IO.ofExcept ((generateOne configured renamed "Generated.Reusable").mapError toString)
    for suffix in [".Types", ".Tx", ".Checks"] do
      check s!"schema and handler labels do not change {suffix}"
        ((← source plan suffix) == (← source renamedPlan suffix))
    for schema in [Json.mkObj [("dataType", .str "integer")],
        Json.mkObj [("$ref", .str "#/definitions/missing")]] do
      let unsupported := { target with handlers := target.handlers.map fun handler =>
        { handler with datum := handler.datum.map fun argument => { argument with schema } } }
      match generateOne configured unsupported "Generated.Unsupported" with
      | .error error =>
        check "incompatible or unresolved datum schemas skip before execution"
          (error.kind == .unsupported)
      | .ok _ => throw (IO.userError "unsupported reusable schema generated proof jobs")
  IO.println "UP012 reusable preparation generator checks passed."

def run : IO Unit := do
  runUnit
  startCase "UP012: reusable preparation on three new programs"
    "controller PASS; missing signature FAIL; never accepts INCONCLUSIVE displayed ERROR"
    "App.Run.runWith [UP-012 v1 / TxM-009], reusable fixture" 300000
  let configured ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 "TxM-009")
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "reusable tests receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  let id : CheckId := { propertyId := "UP-012", definitionVersion := 1, modelId := "TxM-009" }
  let run ← App.Run.runWith #[id]
    (fun selected => Candidates.Catalogue.loadCheck selected.propertyId selected.definitionVersion selected.modelId)
    { path := fixture, validators := targets, timeoutMs := 300000 }
    { executorOptions := { leanPath }, outputRoot := "output" }
  check "reusable run finishes all three programs" (run.finished && run.exitCode == 0 && run.validators.size == 3)
  check "retained reusable index matches returned run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  for file in ["README.md", "sources/index.json"] do
    check s!"reusable run retains {file}" (← (run.directory / file).pathExists)
  for validator in run.validators do
    check "reusable program has exactly the requested check"
      (validator.preparationError.isNone && validator.checks.size == 1 && validator.checks[0]!.id == id)
    let checkRun := validator.checks[0]!
    let some result := checkRun.result | throw (IO.userError "missing reusable check result")
    let never := validator.name == "never_accept.never_accept"
    let buggy := validator.name == "missing_signature.missing_signature"
    check "independent scenario expectation matches assessed and displayed outcomes"
      (checkRun.error.isNone && result.check == configured.context &&
       result.status == (if never then .inconclusive else if buggy then .fail else .pass) &&
       checkRun.displayStatus == (if never then "ERROR" else if buggy then "FAIL" else "PASS") &&
       checkRun.notRunReason.isNone && !checkRun.timedOut)
    check "reusable obligations preserve metadata and complete evidence"
      (result.obligations.map (·.job.name) == names && result.obligations.all fun row =>
        row.job.expected == .valid && row.job.binding == some configured.context.binding &&
        row.job.txModelId == some "TxM-009" && row.evidenceComplete)
    let some main := result.obligations[0]? | throw (IO.userError "missing property observation")
    let some support := result.obligations[1]? | throw (IO.userError "missing applicability observation")
    check "property observation distinguishes the missing signature"
      (main.observed == some (if buggy then .falsified else .valid))
    check "never accepting program falsifies applicability"
      (support.observed == some (if never then .falsified else .valid))
    let some input := result.evidence.find? (·.fileName == some "input.json")
      | throw (IO.userError "missing reusable input evidence")
    let some directory := input.parent | throw (IO.userError "missing reusable evidence directory")
    IO.println s!"Reusable check result: {directory / "check-result.json"}"
    showCompilerLogs directory
    check "retained reusable result matches observations"
      ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
    for reference in result.evidence do
      check "reusable evidence references retained files" (← reference.pathExists)
  IO.println "UP012 reusable preparation whole-workflow checks passed."

end Workflow.Tests.UP012.ReusableTests

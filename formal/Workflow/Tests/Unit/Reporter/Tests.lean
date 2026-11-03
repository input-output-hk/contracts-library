import Workflow.Reporter

open Lean Workflow
open Workflow.Reporter

namespace Workflow.Tests.Unit.Reporter

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def job (name := "proof") (expected := ExpectedResult.valid) : CheckJob :=
  { propertyId := "fixture", name, moduleName := "Fixture.Checks", statement := "True",
    expected, scope := "fixture scope" }

private def reference (metadata : CheckJob) : JobRef :=
  { moduleName := metadata.moduleName, name := metadata.name }

private def plan (jobs : Array CheckJob) : GenerationPlan :=
  { targetName := "fixture.target", modules := #[], jobs,
    status := if jobs.isEmpty then .noObligations else .ready }

private def observation (metadata : CheckJob) (observed : Executor.ObservedResult) : Executor.JobObservation :=
  { job := metadata, observed, evidenceComplete := true }

private def completed (jobs : Array Executor.JobObservation) : Executor.Result :=
  { state := .completed, jobs }

private def definition (title := "Fixture metadata") : IO PropertyDefinition :=
  IO.ofExcept (PropertyDefinition.parse (Json.mkObj [
    ("schema_version", toJson (2 : Nat)),
    ("identity", Json.mkObj [("id", .str "fixture"),
      ("definition_version", toJson (1 : Nat)), ("title", .str title)]),
    ("formalization", Json.mkObj [("primary", .str "Fixture.Checks.proof")])]))

private def rowFor (report : Report) (metadata : CheckJob) : IO Row :=
  match report.rows.find? (fun row => row.job.name == metadata.name &&
      row.job.moduleName == metadata.moduleName) with
  | some row => pure row
  | none => throw (IO.userError s!"missing report row: {metadata.moduleName}.{metadata.name}")

private def jsonRow (report : Report) (metadata : CheckJob) : IO Json := do
  let rows ← IO.ofExcept do (← report.toJson.getObjVal? "checks").getArr?
  let some row := rows.find? (fun row =>
      (row.getObjVal? "name").toOption == some (.str metadata.name) &&
      (row.getObjVal? "module").toOption == some (.str metadata.moduleName))
    | throw (IO.userError "missing JSON check row")
  return row

private def binding (modelId := "TxM-001") (propertyId := "fixture") (version : Int := 1)
    (description := "Fixture model") (limitation := "Only the fixture domain.") : IO CheckBinding := do
  let txModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj [
    ("id", .str modelId), ("title", .str "Fixture model"), ("plutus_version", .str "v3"),
    ("description", .str description)]))
  let combinedCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str propertyId), ("definition_version", toJson version)]),
    ("tx_model", .str modelId), ("limitations", .arr #[.str limitation])]))
  return { txModel, combinedCheck }

private def modelBindingChecks : IO Unit := do
  let metadata ← definition
  let firstBinding ← binding
  let secondBinding ← binding "TxM-002"
  let described := fun (jobs : Array CheckJob) =>
    { plan jobs with propertyDefinition := some metadata, bindingsRequired := true }
  let executed := fun (rows : Array Executor.JobObservation) =>
    { completed rows with propertyDefinition := some metadata }
  let main := { job "bound" with txModelId := some "TxM-001", binding := some firstBinding }
  let report := build (described #[main]) (executed #[observation main .valid])
  let saved ← jsonRow report main
  check "matching model binding preserves a passing result and exact snapshots"
    (report.exitCode == 0 &&
     (saved.getObjVal? "txModelId").toOption == some (.str "TxM-001") &&
     (saved.getObjVal? "transactionModel").toOption == some firstBinding.txModel.toJson &&
     (saved.getObjVal? "combinedCheck").toOption == some firstBinding.combinedCheck.toJson)
  let changedModel ← binding "TxM-001" "fixture" 1 "Different model description"
  let changedCombination ← binding "TxM-001" "fixture" 1 "Fixture model" "Different limitation"
  for changed in [none, some changedModel, some changedCombination, some secondBinding] do
    let changedJob := { main with binding := changed }
    let altered := build (described #[main]) (executed #[observation changedJob .falsified])
    let row ← rowFor altered main
    let json ← jsonRow altered main
    check "changed or lost snapshots cannot qualify raw failure"
      (altered.exitCode == 2 && row.status == .inconclusive &&
       row.observed == some .falsified && row.evidenceComplete &&
       row.issues.contains "job metadata changed during execution" &&
       (json.getObjVal? "combinedCheck").toOption == some firstBinding.combinedCheck.toJson)
  let alteredMarker := build (described #[main])
    (executed #[observation { main with txModelId := some "TxM-002" } .valid])
  check "changed registered model marker prevents qualification" (alteredMarker.exitCode == 2)

  let wrongProperty ← binding "TxM-001" "other-property"
  let wrongVersion ← binding "TxM-001" "fixture" 2
  let wrongModel := { firstBinding with txModel := secondBinding.txModel }
  for invalidJob in [
      { main with binding := none },
      { main with txModelId := none },
      { main with txModelId := some "TxM-002" },
      { main with binding := some wrongProperty },
      { main with binding := some wrongVersion },
      { main with binding := some wrongModel }] do
    let requested := described #[invalidJob]
    check "invalid binding chain fails plan validation" requested.validateBindings.toOption.isNone
    let invalid := build requested (executed #[observation invalidJob .valid])
    check "invalid planned binding cannot produce a pass"
      (invalid.exitCode == 2 && (← rowFor invalid invalidJob).observed == some .valid &&
       !invalid.problems.isEmpty)
  let conflicting := { main with name := "conflicting", binding := some changedModel }
  let conflictingPlan := described #[main, conflicting]
  check "one model ID cannot carry conflicting snapshots"
    conflictingPlan.validateBindings.toOption.isNone
  let conflictingPair := { main with name := "conflicting", binding := some changedCombination }
  check "one combination cannot carry conflicting snapshots"
    (described #[main, conflictingPair]).validateBindings.toOption.isNone

  let support := { job "support" with
    role := .applicability
    txModelId := some "TxM-001"
    binding := some firstBinding }
  let dependent := { main with applicability := some (reference support) }
  for (observed, expectedCode) in
      [(Executor.ObservedResult.valid, (0 : UInt32)), (.falsified, 1), (.inconclusive, 2)] do
    let qualified := build (described #[dependent, support])
      (executed #[observation dependent observed, observation support .valid])
    check "same-model applicability qualifies only the property's own result"
      (qualified.exitCode == expectedCode && (← rowFor qualified dependent).observed == some observed)
  let foreignSupport := { support with txModelId := some "TxM-002", binding := some secondBinding }
  let independent := { job "independent" with txModelId := some "TxM-002", binding := some secondBinding }
  for observed in [Executor.ObservedResult.valid, .falsified] do
    let crossModel := build (described #[dependent, foreignSupport, independent])
      (executed #[observation dependent observed, observation foreignSupport .valid,
        observation independent .falsified])
    let row ← rowFor crossModel dependent
    check "valid applicability from another model cannot qualify either main outcome"
      (row.status == .inconclusive && row.observed == some observed &&
       row.issues.contains "invalid applicability reference: property and support use different model bindings")
    check "cross-model support does not hide an independent trusted failure"
      ((← rowFor crossModel independent).status == .fail && crossModel.exitCode == 1)

  let escapedBinding ← binding "TxM-001" "fixture" 1 "First\nSecond\tThird\rFourth" "Scope\nline"
  let escapedJob := { main with binding := some escapedBinding }
  let escaped := build (described #[escapedJob]) (executed #[observation escapedJob .valid])
  let escapedJson ← jsonRow escaped escapedJob
  check "model text escapes line and control characters without changing JSON"
    ((escaped.text.splitOn "Model description: First\\nSecond\\tThird\\rFourth").length == 2 &&
     (escaped.text.splitOn "First\nSecond").length == 1 &&
     (escapedJson.getObjVal? "transactionModel").toOption == some escapedBinding.txModel.toJson &&
     (escapedJson.getObjVal? "combinedCheck").toOption == some escapedBinding.combinedCheck.toJson)
  check "model and combination fields use simple report labels"
    ((escaped.text.splitOn "  Model: TxM-001").length == 2 &&
     (escaped.text.splitOn "  Plutus version: v3").length == 2 &&
     (escaped.text.splitOn "  Combination limitations:").length == 2)
  let plain := build (plan #[job]) (completed #[observation job .valid])
  let plainJson ← jsonRow plain job
  check "metadata-free API reports invent no model record"
    ((plainJson.getObjVal? "transactionModel").toOption == some .null &&
     (plainJson.getObjVal? "combinedCheck").toOption == some .null &&
     (plain.text.splitOn "  Model:").length == 1)

def run : IO Unit := do
  modelBindingChecks
  let good := build (plan #[job]) (completed #[observation job .valid])
  check "matching result passes" (good.status == .pass && good.exitCode == 0)
  let bad := build (plan #[job]) (completed #[observation job .falsified])
  check "unexpected counterexample fails" (bad.status == .fail && bad.exitCode == 1)
  let witness := job "witness" .falsified
  let found := build (plan #[witness]) (completed #[observation witness .falsified])
  check "expected counterexample can pass" (found.status == .pass && found.exitCode == 0)
  let missingWitness := build (plan #[witness]) (completed #[observation witness .valid])
  check "unexpected valid result fails a witness job" (missingWitness.exitCode == 1)
  let unknown := build (plan #[job]) (completed #[observation job .inconclusive])
  check "unknown does not pass" (unknown.status == .inconclusive && unknown.exitCode == 2)
  let ordinary := job "ordinary_applies"
  let ordinaryFailure := build (plan #[ordinary]) (completed #[observation ordinary .falsified])
  check "job names do not infer applicability roles" (ordinaryFailure.status == .fail)

  let metadata ← definition
  for (metadataJob, observed, expectedCode) in
      [(job, Executor.ObservedResult.valid, (0 : UInt32)),
       (job, .falsified, 1), (witness, .falsified, 0)] do
    let report := build { plan #[metadataJob] with propertyDefinition := some metadata }
      { completed #[observation metadataJob observed] with propertyDefinition := some metadata }
    check "matching property metadata retains actual result policy" (report.exitCode == expectedCode)
    check "report retains the plan's property metadata snapshot"
      (report.propertyDefinition == some metadata &&
       (report.toJson.getObjVal? "propertyDefinition").toOption == some metadata.toJson)
  let changedMetadata ← definition "Different metadata"
  for (plannedMetadata, executedMetadata) in
      [(some metadata, none), (none, some metadata), (some metadata, some changedMetadata)] do
    for observed in [Executor.ObservedResult.valid, .falsified] do
      let report := build { plan #[job] with propertyDefinition := plannedMetadata }
        { completed #[observation job observed] with propertyDefinition := executedMetadata }
      let row ← rowFor report job
      check "mismatched property metadata prevents qualification without erasing raw evidence"
        (report.exitCode == 2 && row.status == .inconclusive &&
         row.observed == some observed && row.evidenceComplete &&
         report.problems.contains "property definition metadata changed during execution")
      check "metadata mismatch keeps the plan snapshot rather than the execution replacement"
        (report.propertyDefinition == plannedMetadata)
  let preparationFailure := failure "fixture.target" "unsupported fixture" (some metadata)
  check "preparation failure retains known property metadata without inventing results"
    (preparationFailure.exitCode == 2 && preparationFailure.rows.isEmpty &&
     preparationFailure.propertyDefinition == some metadata &&
     (preparationFailure.toJson.getObjVal? "propertyDefinition").toOption == some metadata.toJson)
  check "absent property metadata is explicit and does not invent values"
    (good.propertyDefinition.isNone &&
     (good.toJson.getObjVal? "propertyDefinition").toOption == some .null &&
     (failure "fixture.target" "no selected definition").propertyDefinition.isNone)
  let multilineMetadata ← definition "Fixture\nmetadata"
  let escapedMetadata := failure "fixture.target" "unsupported fixture" (some multilineMetadata)
  check "property metadata text escapes embedded line breaks"
    ((escapedMetadata.text.splitOn "Fixture\\nmetadata").length == 2 &&
     (escapedMetadata.text.splitOn "Fixture\nmetadata").length == 1 &&
     (escapedMetadata.toJson.getObjVal? "propertyDefinition").toOption == some multilineMetadata.toJson)

  for state in [Executor.RunState.timedOut, .error, .noObligations] do
    let report := build (plan #[job])
      { completed #[{ observation job .valid with evidenceComplete := false }] with state }
    let row ← rowFor report job
    check "partial positive evidence remains inconclusive and visible"
      (report.exitCode == 2 && row.status == .inconclusive &&
       row.observed == some .valid && !row.evidenceComplete)
  let errored := build (plan #[job])
    { completed #[observation job .valid] with problems := #["unrelated compiler problem"] }
  check "aggregate problems preserve trusted rows but leave the run incomplete"
    (errored.exitCode == 2 && (← rowFor errored job).status == .pass)
  let rowIssue := build (plan #[job])
    (completed #[{ observation job .valid with issues := #["conflicting evidence"] }])
  check "job problem overrides positive evidence" (rowIssue.exitCode == 2)
  let absent := build (plan #[job]) (completed #[])
  check "missing observation is inconclusive" (absent.exitCode == 2)
  let duplicate := build (plan #[job]) (completed #[observation job .valid, observation job .valid])
  check "duplicate observation is inconclusive" (duplicate.exitCode == 2)
  for changedJob in [{ job with expected := .falsified }, { job with scope := "different" },
      { job with role := .applicability },
      { job with applicability := some { moduleName := "Other.Checks", name := "scenario" } }] do
    let report := build (plan #[job]) (completed #[observation changedJob .valid])
    check "changed execution metadata remains inconclusive" (report.exitCode == 2)
  let empty := build (plan #[]) { state := .noObligations }
  check "empty plan is not a pass" (empty.status == .inconclusive && empty.exitCode == 2)

  let done := job "done"
  let pending := job "pending"
  for state in [Executor.RunState.timedOut, .error] do
    for (observed, expectedStatus, expectedCode) in
        [(Executor.ObservedResult.valid, Status.pass, (2 : UInt32)), (.falsified, .fail, 1)] do
      let report := build (plan #[done, pending]) {
        completed #[observation done observed,
          { observation pending .valid with evidenceComplete := false }] with
        state, problems := #["another module did not complete"] }
      check "independent trustworthy row survives another module's failure"
        ((← rowFor report done).status == expectedStatus)
      check "partial module marker cannot qualify its raw result"
        ((← rowFor report pending).status == .inconclusive &&
         (← rowFor report pending).observed == some .valid)
      check "qualified failure outranks an incomplete run" (report.exitCode == expectedCode)
  let mixed := build (plan #[job, witness])
    (completed #[observation job .falsified, observation witness .inconclusive])
  check "qualified failure takes precedence over inconclusive" (mixed.exitCode == 1)

  let claimSupport := { job "scenario" with moduleName := "Fixture.Claim", role := .applicability }
  let cancelSupport := { job "scenario" with moduleName := "Fixture.Cancel", role := .applicability }
  let claim := { job "claim" with applicability := some (reference claimSupport) }
  let cancel := { job "cancel" with applicability := some (reference cancelSupport) }
  let independent := job "independent"
  for (observed, expectedStatus, expectedCode) in
      [(Executor.ObservedResult.valid, Status.pass, (0 : UInt32)), (.falsified, .fail, 1)] do
    let report := build (plan #[claim, claimSupport])
      (completed #[observation claim observed, observation claimSupport .valid])
    check "trustworthy valid applicability qualifies the property"
      ((← rowFor report claim).status == expectedStatus &&
       (← rowFor report claimSupport).status == .pass && report.exitCode == expectedCode)
  let separate := build (plan #[claim, claimSupport, cancel, cancelSupport])
    (completed #[observation claim .falsified, observation claimSupport .valid,
      observation cancel .valid, observation cancelSupport .falsified])
  check "claim and cancel use their separate module-qualified references"
    ((← rowFor separate claim).status == .fail && (← rowFor separate cancel).status == .inconclusive &&
     (← rowFor separate cancelSupport).status == .inconclusive && separate.exitCode == 1)

  for observed in [Executor.ObservedResult.valid, .falsified] do
    let report := build (plan #[claim, claimSupport])
      (completed #[observation claim observed, observation claimSupport .falsified])
    let propertyRow ← rowFor report claim
    let supportRow ← rowFor report claimSupport
    check "known false applicability is not a failing property"
      (report.exitCode == 2 && propertyRow.status == .inconclusive && supportRow.status == .inconclusive)
    check "unqualified property retains its own completed raw observation"
      (propertyRow.observed == some observed && propertyRow.evidenceComplete &&
       supportRow.observed == some .falsified && supportRow.evidenceComplete)
  for (observed, complete) in [(Executor.ObservedResult.inconclusive, true), (.valid, false), (.falsified, false)] do
    let report := build (plan #[claim, claimSupport])
      (completed #[observation claim .falsified,
        { observation claimSupport observed with evidenceComplete := complete }])
    check "unknown or incomplete applicability cannot qualify a counterexample"
      ((← rowFor report claim).status == .inconclusive &&
       (← rowFor report claimSupport).status == .inconclusive && report.exitCode == 2)
    check "unavailable applicability retains raw evidence"
      ((← rowFor report claim).observed == some .falsified &&
       (← rowFor report claimSupport).observed == some observed)
  let missingSupport := build (plan #[claim, claimSupport, independent])
    (completed #[observation claim .falsified, observation independent .valid])
  check "missing applicability blocks only its linked property"
    ((← rowFor missingSupport claim).status == .inconclusive &&
     (← rowFor missingSupport claimSupport).observed.isNone &&
     (← rowFor missingSupport independent).status == .pass && missingSupport.exitCode == 2)
  let duplicateSupport := build (plan #[claim, claimSupport, independent])
    (completed #[observation claim .falsified, observation claimSupport .valid,
      observation claimSupport .valid, observation independent .valid])
  check "duplicate applicability evidence cannot qualify a property"
    ((← rowFor duplicateSupport claim).status == .inconclusive &&
     (← rowFor duplicateSupport claimSupport).status == .inconclusive &&
     (← rowFor duplicateSupport independent).status == .pass && duplicateSupport.exitCode == 2)
  for changedSupport in [{ claimSupport with role := .property },
      { claimSupport with scope := "changed" },
      { claimSupport with applicability := some (reference cancelSupport) }] do
    let report := build (plan #[claim, claimSupport, independent])
      (completed #[observation claim .falsified, observation changedSupport .valid,
        observation independent .valid])
    check "tampered applicability metadata cannot qualify a property"
      ((← rowFor report claim).status == .inconclusive &&
       (← rowFor report claimSupport).status == .inconclusive &&
       (← rowFor report independent).status == .pass && report.exitCode == 2)

  for (label, jobs) in [
      ("missing reference", #[{ claim with applicability := some { moduleName := "Fixture.Missing", name := "scenario" } }, independent]),
      ("wrong module", #[{ claim with applicability := some { moduleName := "Fixture.Wrong", name := claimSupport.name } }, claimSupport, independent]),
      ("wrong role", #[{ claim with applicability := some (reference independent) }, independent]),
      ("self reference", #[{ claim with applicability := some (reference claim) }, independent]),
      ("different property", #[claim, { claimSupport with propertyId := "other-property" }, independent])] do
    let report := build (plan jobs) (completed (jobs.map fun metadata =>
      observation metadata (if metadata.name == claim.name then .falsified else .valid)))
    check s!"{label}: invalid link prevents qualification"
      ((← rowFor report claim).status == .inconclusive &&
       (← rowFor report claim).observed == some .falsified &&
       (← rowFor report independent).status == .pass && report.exitCode == 2)
  for invalidSupport in [{ claimSupport with applicability := some (reference cancelSupport) },
      { claimSupport with expected := .falsified }] do
    let report := build (plan #[claim, invalidSupport, cancelSupport, independent])
      (completed #[observation claim .falsified, observation invalidSupport .valid,
        observation cancelSupport .valid, observation independent .valid])
    check "invalid applicability plans block their dependent property"
      ((← rowFor report invalidSupport).status == .inconclusive &&
       (← rowFor report claim).status == .inconclusive &&
       (← rowFor report independent).status == .pass && report.exitCode == 2)

  for (label, requested, execution) in [
      ("duplicate planned identity", plan #[job, job], completed #[observation job .falsified]),
      ("unrequested observation", plan #[job, independent], completed #[observation job .falsified,
        observation independent .valid, observation (job "unrequested") .valid]),
      ("status/count mismatch", { plan #[job, independent] with status := .noObligations },
        completed #[observation job .falsified, observation independent .valid])] do
    let report := build requested execution
    check s!"{label}: global structure corruption remains conservative"
      (report.exitCode == 2 && report.rows.all (·.status == .inconclusive) && !report.problems.isEmpty)
  let invalidEmpty := build { plan #[] with status := .ready } (completed #[])
  check "empty status/count mismatch cannot pass" (invalidEmpty.exitCode == 2)

  let first ← jsonRow good job
  check "JSON keeps expectation" ((first.getObjVal? "expected").toOption == some (.str "valid"))
  check "JSON keeps observed result" ((first.getObjVal? "observed").toOption == some (.str "valid"))
  check "JSON keeps scope" ((first.getObjVal? "scope").toOption == some (.str "fixture scope"))
  check "JSON records role and evidence completeness"
    ((first.getObjVal? "role").toOption == some (.str "property") &&
     (first.getObjVal? "evidenceComplete").toOption == some (.bool true) &&
     (first.getObjVal? "applicability").toOption == some .null)
  let partialReport := build (plan #[job])
    (completed #[{ observation job .valid with evidenceComplete := false }])
  let partialJson ← jsonRow partialReport job
  check "JSON preserves incomplete evidence without erasing the raw marker"
    ((partialJson.getObjVal? "evidenceComplete").toOption == some (.bool false) &&
     (partialJson.getObjVal? "observed").toOption == some (.str "valid"))
  let missingJson ← jsonRow missingSupport claimSupport
  check "JSON distinguishes missing observations from raw solver outcomes"
    ((missingJson.getObjVal? "observed").toOption == some .null &&
     (missingJson.getObjVal? "evidenceComplete").toOption == some (.bool false))
  let unqualified := build (plan #[claim, claimSupport])
    (completed #[observation claim .falsified, observation claimSupport .falsified])
  let propertyJson ← jsonRow unqualified claim
  let supportJson ← jsonRow unqualified claimSupport
  let prerequisite ← IO.ofExcept (propertyJson.getObjVal? "applicability")
  check "JSON records the exact applicability reference"
    ((prerequisite.getObjVal? "module").toOption == some (.str claimSupport.moduleName) &&
     (prerequisite.getObjVal? "name").toOption == some (.str claimSupport.name))
  check "JSON retains unqualified raw failure and completed evidence"
    ((propertyJson.getObjVal? "status").toOption == some (.str "INCONCLUSIVE") &&
     (propertyJson.getObjVal? "observed").toOption == some (.str "falsified") &&
     (propertyJson.getObjVal? "evidenceComplete").toOption == some (.bool true))
  check "JSON distinguishes applicability role and raw absence"
    ((supportJson.getObjVal? "role").toOption == some (.str "applicability") &&
     (supportJson.getObjVal? "observed").toOption == some (.str "falsified"))
  let unqualifiedRow ← rowFor unqualified claim
  check "inconclusive row explains its applicability issue" (!unqualifiedRow.issues.isEmpty &&
    (unqualified.text.splitOn ((unqualifiedRow.issues[0]!.splitOn "\n").head!.trim)).length > 1)
  check "plain text contains result and summary"
    ((good.text.splitOn "PASS fixture proof").length == 2 &&
      (good.text.splitOn "Overall: PASS (exit 0)").length == 2)
  check "plain summary matches fixture"
    (good.text == (← IO.FS.readFile "Workflow/Tests/Unit/Reporter/Fixtures/summary.txt"))
  let escaped := failure "target\nname" "problem\ntext"
  check "plain text escapes line breaks" ((escaped.text.splitOn "Target: target\\nname").length == 2)
  IO.FS.withTempDir fun directory => do
    good.write directory
    check "text report written" ((← IO.FS.readFile (directory / "report.txt")) == good.text)
    let saved ← IO.FS.readFile (directory / "report.json")
    check "JSON report written" ((Json.parse saved).toOption == some good.toJson)
  IO.println "Reporter fixture checks passed."

end Workflow.Tests.Unit.Reporter

def main : IO Unit := Workflow.Tests.Unit.Reporter.run

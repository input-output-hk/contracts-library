import Workflow.App.Run

namespace Workflow.Tests.Unit.App

open Lean Workflow Workflow.App Workflow.Generator

private def ensure (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def contains (text fragment : String) : Bool := (text.splitOn fragment).length > 1

private def jsonFile (path : System.FilePath) : IO Json :=
  do IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def field (value : Json) (name : String) : IO Json := IO.ofExcept (value.getObjVal? name)

private def array (value : Json) (name : String) : IO (Array Json) :=
  do IO.ofExcept ((← field value name).getArr?)

private def identity (model : String) (property := "fixture") : CheckId :=
  { propertyId := property, definitionVersion := 1, modelId := model }

private def registry : Array CheckId := #[
  identity "TxM-support", identity "TxM-fail", identity "TxM-slow",
  identity "TxM-unsupported", identity "TxM-empty", identity "TxM-other" "other"]

private def context (id : CheckId) : IO CheckContext := do
  let propertyDefinition ← IO.ofExcept (PropertyDefinition.parse (Json.mkObj [
    ("identity", Json.mkObj [("id", .str id.propertyId),
      ("definition_version", toJson id.definitionVersion)])]))
  let txModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj [
    ("id", .str id.modelId), ("plutus_version", .str "v3"),
    ("description", .str "Controlled app test model")]))
  let combinedCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str id.propertyId),
      ("definition_version", toJson id.definitionVersion)]),
    ("tx_model", .str id.modelId), ("limitations", .arr #[.str "App control only"])]))
  return { propertyDefinition, binding := { combinedCheck, txModel } }

private def fixtureCheck (id : CheckId) : IO ConfiguredCheck := do
  let context ← context id
  let mode := match id.modelId with
    | "TxM-support" => "support"
    | "TxM-fail" => "falsified"
    | "TxM-slow" => "partial"
    | "TxM-input-error" => "input-write-error"
    | "TxM-manifest-error" => "manifest-write-error"
    | "TxM-log-error" => "log-write-error"
    | "TxM-log-full" => "log-full"
    | _ => "valid"
  return {
    context
    generate := fun target modulePrefix => do
      if id.modelId == "TxM-unsupported" then
        throw ⟨.unsupported, "unsupported app fixture"⟩
      if id.modelId == "TxM-empty" then
        return { targetName := target.name, modules := #[], jobs := #[] }
      let moduleName := if mode == "log-write-error" || mode == "log-full" then "Other.Checks"
        else s!"{modulePrefix}.Checks"
      let goal := if mode == "falsified" then "False" else "True"
      let main : CheckJob := {
        propertyId := id.propertyId, name := "property", moduleName,
        statement := goal, expected := .valid, scope := "Controlled app test",
        txModelId := some id.modelId }
      let support : CheckJob := {
        main with name := "support", statement := "True", role := .applicability }
      let jobs := if mode == "support" then
        #[{ main with applicability := some { moduleName, name := "support" } }, support]
        else #[main]
      let source := s!"-- {mode}\n\ntheorem property : {goal} := by trivial\n" ++
        (if mode == "support" then "theorem support : True := by trivial\n" else "")
      return { targetName := target.name, modules := #[⟨moduleName, source⟩], jobs } }

private def load (id : CheckId) : IO (Except String ConfiguredCheck) :=
  do return .ok (← fixtureCheck id)

private def blueprint (entries : Array (String × String)) : String :=
  (Json.mkObj [
    ("preamble", Json.mkObj [("plutusVersion", .str "v3")]),
    ("validators", .arr (entries.map fun (title, code) => Json.mkObj [
      ("title", .str title), ("compiledCode", .str code),
      ("redeemer", Json.mkObj [("schema", Json.mkObj [("dataType", .str "integer")])])]))]).pretty

private def validCode : String := "480100002221200101"

private def sample : String := blueprint #[
  ("samples.alpha.spend", validCode), ("samples.alpha.else", validCode),
  ("other.beta.mint", validCode)]

private def options (outputRoot : System.FilePath) : IO Run.Options := do
  return { outputRoot, executorOptions := {
    leanPath := ".", leanCommand := (← IO.appPath).toString, budgetMs := 5000 } }

private def request (path : System.FilePath) (timeoutMs := 5000) : Request :=
  { path, timeoutMs }

private def checkAt (run : RunRecord) (name model : String) : IO CheckRun := do
  let some validator := run.validators.find? (·.name == name)
    | throw (IO.userError s!"missing validator: {name}")
  let some item := validator.checks.find? (·.id.modelId == model)
    | throw (IO.userError s!"missing model: {model}")
  return item

private def resultAt (run : RunRecord) (name model : String) : IO Assessor.CheckResult := do
  let some result := (← checkAt run name model).result
    | throw (IO.userError s!"missing assessed result: {name}/{model}")
  return result

private def assertSaved (run : RunRecord) : IO Unit := do
  let index ← jsonFile (run.directory / "run.json")
  ensure "saved index matches the returned record" (index == run.toJson)
  ensure "run index contains no overall verdict or copied counts"
    ((index.getObjVal? "status").toOption.isNone &&
     (index.getObjVal? "counts").toOption.isNone &&
     (index.getObjVal? "overall").toOption.isNone)
  let indexedValidators ← array index "validators"
  for validatorIndex in [:run.validators.size] do
    let validator := run.validators[validatorIndex]!
    let indexedChecks ← array indexedValidators[validatorIndex]! "checks"
    for checkIndex in [:validator.checks.size] do
      let item := validator.checks[checkIndex]!
      let indexedCheck := indexedChecks[checkIndex]!
      let expectedNotRun := if validator.preparationError.isSome then Json.null else
        match item.notRunReason with
        | some .notApplicable => .str "not_applicable"
        | some .unsupported => .str "unsupported"
        | none => .null
      ensure "index persists only the guarded non-execution reason"
        ((← field indexedCheck "not_run") == expectedNotRun &&
         (← field indexedCheck "timed_out") == .bool (validator.preparationError.isNone && item.timedOut) &&
         (indexedCheck.getObjVal? "status").toOption.isNone &&
         (indexedCheck.getObjVal? "counts").toOption.isNone)
      if let some result := item.result then
        let some reference := item.resultFile
          | throw (IO.userError "assessed result has no retained reference")
        ensure "result index paths are relative" (!reference.isAbsolute)
        let savedPath := run.directory / reference
        ensure "saved check result matches the returned record"
          ((← jsonFile savedPath) == result.toJson)
        let resolved ← IO.FS.realPath savedPath
        ensure "check results stay inside their run's validator folders"
          (resolved.toString.startsWith ((run.directory / "validators").toString ++ "/"))
        ensure "saved results preserve validator and requested combination identity"
          (result.target.name == validator.name &&
           result.check.propertyDefinition.id? == some item.id.propertyId &&
           result.check.propertyDefinition.version? == some item.id.definitionVersion &&
           result.check.binding.txModel.id? == some item.id.modelId)
        for evidence in result.evidence do
          ensure "advertised check evidence exists" (← evidence.pathExists)
      else
        ensure "no result path is invented for missing check outcomes" item.resultFile.isNone

private def countsAndContinuation (temporary path : System.FilePath) : IO Unit := do
  let run ← Run.runWith registry load (request path 2000) (← options (temporary / "counts"))
  ensure "all logical validators are selected once in blueprint order"
    (run.validators.map (·.name) == #["samples.alpha", "other.beta"])
  ensure "all model pairings are selected for every validator"
    (run.validators.all fun validator => validator.checks.map (·.id) == registry)
  ensure "completed mixed verification is an operational success" (run.finished && run.exitCode == 0)
  for name in #["samples.alpha", "other.beta"] do
    let supported ← resultAt run name "TxM-support"
    ensure "support obligations remain inside one passing combination"
      (supported.status == .pass && supported.obligations.size == 2)
    ensure "falsified obligations remain failing results"
      ((← resultAt run name "TxM-fail").status == .fail)
    ensure "timeouts remain inconclusive"
      ((← resultAt run name "TxM-slow").status == .inconclusive)
    let unsupported ← checkAt run name "TxM-unsupported"
    ensure "unsupported combinations remain explained inconclusive attempts"
      (unsupported.result.any (·.status == .inconclusive) &&
       unsupported.notRunReason == some .unsupported && unsupported.displayStatus == "SKIPPED" &&
       !(← resultAt run name "TxM-unsupported").reasons.isEmpty)
    let empty ← checkAt run name "TxM-empty"
    ensure "empty generation is not applicable without becoming a pass"
      (empty.result.any (fun result => result.status == .inconclusive && result.obligations.isEmpty) &&
       empty.notRunReason == some .notApplicable && empty.displayStatus == "SKIPPED")
    let slow ← checkAt run name "TxM-slow"
    ensure "timeouts are never counted as non-execution"
      (slow.notRunReason.isNone && slow.displayStatus == "TIMEOUT" && slow.timedOut)
    ensure "later checks receive a fresh budget and still run"
      ((← resultAt run name "TxM-other").status == .pass)
  ensure "terminal counts combinations rather than supporting obligations"
    (contains run.text "Recorded checks: 12/12")
  for name in #["samples.alpha", "other.beta"] do
    let some row := (run.text.splitOn "\n").find? (·.startsWith name)
      | throw (IO.userError s!"missing terminal row: {name}")
    let columns := (row.splitOn " ").filter (!·.isEmpty)
    ensure "terminal displays one count per assessed combination"
      (columns == [name, "2", "1", "2", "0", "1"])
  ensure "terminal has a count table and output reference without overall verdict"
    (contains run.text "Validator" && contains run.text "TIMEOUT" &&
     contains run.text "Output: " && !contains run.text "Overall:")
  let lines := run.text.splitOn "\n"
  ensure "table separator matches the displayed header width"
    ((lines[2]?.getD "").length == (lines[3]?.getD "").length)
  ensure "terminal defines all five outcomes immediately below the table"
    (contains run.text "\n\nKey:\n  PASS: met the check expectations within its model, assumptions, and bounds." &&
     contains run.text "  FAIL: did not meet the check expectations;" &&
     contains run.text "  SKIPPED: not applicable or unsupported for this validator/model combination." &&
     contains run.text "  ERROR: no reliable result for another reason; see the recorded details." &&
     contains run.text "  TIMEOUT: verification exceeded its execution time limit.")
  let later ← checkAt run "samples.alpha" "TxM-other"
  let some reference := later.resultFile | throw (IO.userError "missing later check reference")
  let some folder := (run.directory / reference).parent | throw (IO.userError "missing later check folder")
  let progress ← jsonFile (folder / "index-before-compiler.json")
  let progressValidators ← array progress "validators"
  let earlierChecks ← array progressValidators[0]! "checks"
  ensure "index checkpoints earlier outcomes before a later compiler starts"
    ((← field progress "finished") == .bool false &&
     (earlierChecks.filter fun check =>
       (check.getObjVal? "result").toOption.any (· != .null)).size == 5)
  assertSaved run

private def displayGuards (temporary path : System.FilePath) : IO Unit := do
  let generated ← Run.runWith #[identity "TxM-unsupported"] load (request path)
    (← options (temporary / "display-guards"))
  let tagged ← checkAt generated "samples.alpha" "TxM-unsupported"
  let some result := tagged.result | throw (IO.userError "missing tagged fixture result")
  let missing : CheckRun := { id := tagged.id }
  let blank : CheckRun := { tagged with result := some { result with notRun := none, reasons := #[] } }
  let failed : CheckRun := { tagged with error := some "retention failed" }
  let passing : CheckRun := { tagged with result := some { result with status := .pass } }
  let timeout : CheckRun := { blank with result := some { result with notRun := none, timedOut := true } }
  let errorTimeout : CheckRun := { timeout with error := some "retention failed" }
  let reasonOnly : CheckRun := { blank with result := some {
    result with notRun := none, reasons := #["timeout reported in ordinary error text"] } }
  let falsifiedApplicability : CheckRun := { blank with result := some {
    result with notRun := none, reasons := #["Applicability obligation was falsified"] } }
  ensure "typed timeout evidence alone selects the timeout group"
    (timeout.displayStatus == "TIMEOUT" && timeout.timedOut &&
     (← field timeout.toJson "timed_out") == .bool true)
  for check in #[errorTimeout, reasonOnly, falsifiedApplicability] do
    ensure "errors and untyped inconclusive reasons do not become timeouts or skips"
      (check.displayStatus == "ERROR" && !check.timedOut && check.notRunReason.isNone &&
       (← field check.toJson "timed_out") == .bool false &&
       (← field check.toJson "not_run") == .null)
  for check in #[missing, blank, failed] do
    ensure "missing, blank, and operationally failed outcomes never become skips"
      (check.displayStatus == "ERROR" && check.notRunReason.isNone &&
       (← field check.toJson "not_run") == .null)
  let staleTimeout : CheckRun := { passing with result := some { result with status := .pass, timedOut := true } }
  ensure "qualified results and skip tags suppress stale timeout evidence"
    (!staleTimeout.timedOut && staleTimeout.displayStatus == "PASS" &&
     !({ tagged with result := some { result with timedOut := true } } : CheckRun).timedOut)
  ensure "non-execution tags cannot override assessed pass or fail"
    (passing.displayStatus == "PASS" && passing.notRunReason.isNone &&
     ({ passing with result := some { result with status := .fail } } : CheckRun).displayStatus == "FAIL")
  let guards : RunRecord := { directory := temporary, finished := true, validators := #[
    { name := "guards", checks := #[missing, blank, failed] },
    { name := "preparation", preparationError := some "could not prepare", checks := #[tagged, timeout] }] }
  for (name, expected) in #[("guards", ["guards", "0", "0", "0", "3", "0"]),
      ("preparation", ["preparation", "0", "0", "0", "2", "0"])] do
    let some row := (guards.text.splitOn "\n").find? (·.startsWith name)
      | throw (IO.userError s!"missing guard row: {name}")
    ensure "unresolved combinations and preparation failures count as errors"
      ((row.splitOn " ").filter (!·.isEmpty) == expected)
  let validators ← array guards.toJson "validators"
  let checks ← array validators[1]! "checks"
  ensure "preparation failure suppresses non-execution metadata"
    ((← field checks[0]! "not_run") == .null &&
     (← field checks[1]! "timed_out") == .bool false)

private def preparationIsolation (temporary path : System.FilePath) : IO Unit := do
  IO.FS.writeFile path (blueprint #[
    ("bad.broken.spend", "zz"), ("good.working.spend", validCode)])
  let one := #[identity "TxM-support"]
  let run ← Run.runWith one load (request path) (← options (temporary / "isolation"))
  ensure "one invalid validator does not prevent another from running"
    (run.validators.size == 2 && run.validators[0]!.preparationError.isSome &&
     run.validators[0]!.checks.all (·.result.isNone) &&
     (← resultAt run "good.working" "TxM-support").status == .pass)
  ensure "preparation problems remain visible to callers and terminal"
    (run.exitCode == 2 && contains run.text "Preparation error")
  assertSaved run
  IO.FS.writeFile path sample

private def selectionChecks (temporary path : System.FilePath) : IO Unit := do
  let switches := temporary / "checks with spaces.json"
  IO.FS.writeFile switches "{\"fixture\": false, \"other\": true}"
  let selected : Request := { request path with validators := #["alpha"], checksFile := some switches }
  let run ← Run.runWith registry load selected (← options (temporary / "selected"))
  ensure "switches and validator aliases narrow the selected work"
    (run.validators.map (·.name) == #["samples.alpha"] &&
     run.validators[0]!.checks.map (·.id) == #[identity "TxM-other" "other"])
  ensure "selection snapshot is retained"
    ((← IO.FS.readFile (run.directory / "checks.json")) == "{\"fixture\": false, \"other\": true}")
  assertSaved run
  IO.FS.writeFile switches "{}"
  let empty ← Run.runWith registry load selected (← options (temporary / "empty"))
  ensure "an explicitly empty selection is a visible successful no-op"
    (empty.finished && empty.exitCode == 0 &&
     empty.validators.all (·.checks.isEmpty) && contains empty.text "No checks selected")
  assertSaved empty
  IO.FS.writeFile switches "{\"unknown\": true}"
  let calls ← IO.mkRef (0 : Nat)
  let uncalled := fun id => do calls.modify (· + 1); load id
  let invalid ← Run.runWith registry uncalled selected (← options (temporary / "invalid-selection"))
  ensure "invalid selection aborts before executable resolution"
    ((← calls.get) == 0 && invalid.exitCode == 2 && !invalid.errors.isEmpty)
  assertSaved invalid

private def identityAndSnapshot (temporary path : System.FilePath) : IO Unit := do
  let single := #[identity "TxM-support"]
  let wrong := fun (_ : CheckId) => load (identity "TxM-other" "other")
  let mismatch ← Run.runWith single wrong (request path) (← options (temporary / "wrong-identity"))
  ensure "a resolver cannot execute a different property/model under the requested identity"
    (mismatch.exitCode == 2 && mismatch.validators.all fun validator =>
      validator.checks.all fun check => check.result.isNone && check.error.isSome && check.displayStatus == "ERROR")
  assertSaved mismatch

  let outputRoot := temporary / "snapshot"
  let firstCall ← IO.mkRef true
  let inspect := fun id => do
    if ← firstCall.get then
      firstCall.set false
      let children ← outputRoot.readDir
      ensure "the app allocates one root before resolving checks" (children.size == 1)
      let some child := children[0]? | throw (IO.userError "missing run directory")
      let pending ← jsonFile (child.path / "run.json")
      ensure "index begins unfinished" ((← field pending "finished") == .bool false)
      let validators ← array pending "validators"
      ensure "every selected validator is indexed before checks start" (validators.size == 2)
      for validator in validators do
        let checks ← array validator "checks"
        ensure "planned identities exist without invented result references"
          (checks.size == 1 && checks.all fun check =>
            (check.getObjVal? "result").toOption == some .null)
      IO.FS.writeFile path "changed after capture"
    load id
  let captured ← Run.runWith single inspect (request path) (← options outputRoot)
  ensure "all preparations use the original captured blueprint"
    (captured.validators.size == 2 && captured.validators.all (·.preparationError.isNone) &&
     captured.validators.all fun validator => validator.checks.all fun check =>
       check.result.any (·.status == .pass))
  ensure "root input is the captured source" ((← IO.FS.readFile (captured.directory / "input.json")) == sample)
  for validator in captured.validators do
    for check in validator.checks do
      let some reference := check.resultFile | throw (IO.userError "missing captured result")
      let some parent := (captured.directory / reference).parent | throw (IO.userError "missing check folder")
      ensure "each check uses the same captured source" ((← IO.FS.readFile (parent / "input.json")) == sample)
  assertSaved captured
  IO.FS.writeFile path sample

private def outputIsolation (temporary path : System.FilePath) : IO Unit := do
  let encoded := #["a/b.alpha", "a%2Fb.alpha", "../x.alpha", ".", "..", "ordinary.name"].map Run.safeName
  ensure "safe names are distinct path segments"
    ((encoded.toList.eraseDups.length == encoded.size) &&
     encoded.all fun name => !name.isEmpty && !contains name "/" && name != "." && name != "..")
  IO.FS.writeFile path (blueprint #[
    ("folder/module.alpha.spend", validCode), ("folder%2Fmodule.alpha.spend", validCode)])
  let outputRoot := temporary / "preserved"
  let first ← Run.runWith #[identity "TxM-support"] load (request path) (← options outputRoot)
  let earlier ← IO.FS.readFile (first.directory / "run.json")
  let second ← Run.runWith #[identity "TxM-support"] load (request path) (← options outputRoot)
  ensure "run roots are unique and earlier output stays intact"
    (first.directory != second.directory &&
     (← IO.FS.readFile (first.directory / "run.json")) == earlier)
  ensure "path-like validator names remain distinct identities"
    (first.validators.map (·.name) == #["folder/module.alpha", "folder%2Fmodule.alpha"])
  assertSaved first
  assertSaved second
  IO.FS.writeFile path sample

private def storageChecks (temporary path : System.FilePath) : IO Unit := do
  let inputError ← Run.runWith #[identity "TxM-input-error"] load (request path)
    (← options (temporary / "input-write-error"))
  ensure "failed captured-input retention cannot look like app success"
    (inputError.exitCode == 2 && inputError.validators.all fun validator =>
      validator.checks.all fun check => check.result.any (·.status == .inconclusive))
  let manifestError ← Run.runWith #[identity "TxM-manifest-error"] load (request path)
    (← options (temporary / "manifest-write-error"))
  for validator in manifestError.validators do
    let result ← resultAt manifestError validator.name "TxM-manifest-error"
    ensure "manifest failures retain an inconclusive result and original source files"
      (result.status == .inconclusive && result.evidence.any (·.extension == some "lean") &&
       result.evidence.any (·.extension == some "attempted"))
  assertSaved manifestError
  for model in #["TxM-log-error", "TxM-log-full"] do
    let logError ← Run.runWith #[identity model, identity "TxM-after-log-error"]
      load (request path) (← options (temporary / model))
    ensure "log-retention errors keep the run operationally unsuccessful"
      (logError.finished && logError.exitCode == 2)
    for validator in logError.validators do
      let affected ← checkAt logError validator.name model
      ensure "log-retention failure preserves an explained linked inconclusive result"
        (affected.error.isSome && affected.resultFile.isSome &&
         affected.result.any (·.status == .inconclusive) &&
         affected.displayStatus == "ERROR" && !affected.timedOut)
      let some reference := affected.resultFile | throw (IO.userError "missing log-failure result")
      let some directory := (logError.directory / reference).parent
        | throw (IO.userError "missing log-failure directory")
      let manifest ← jsonFile (directory / "execution.json")
      ensure "execution manifest records failed log retention"
        (!(← array manifest "retention_errors").isEmpty)
      ensure "storage failure outside the Generated folder still reaches the app"
        (!(← (directory / "Generated").pathExists) &&
         (← (directory / "Other/Checks.lean").pathExists))
      let later ← checkAt logError validator.name "TxM-after-log-error"
      ensure "later checks still run after a log-retention failure"
        (later.error.isNone && later.result.any (·.status == .pass))
    assertSaved logError
  let blocked := temporary / "blocked-output"
  IO.FS.writeFile blocked "cannot be a directory"
  let visible ← try
    let failed ← Run.runWith #[identity "TxM-support"] load (request path) (← options blocked)
    pure (failed.exitCode != 0 && !failed.errors.isEmpty)
  catch error => pure (!error.toString.isEmpty)
  ensure "blocked output storage is a visible operational error" visible

private def directDirectoryChecks (temporary : System.FilePath) : IO Unit := do
  let prepared ← IO.ofExcept ((Input.parse sample "samples.alpha").mapError toString)
  let configured ← fixtureCheck (identity "TxM-support")
  let workspace := temporary / "direct-workspace"
  let execution := (← options (temporary / "unused-root")).executorOptions
  let engine : Verification.Engine := { options := { execution with directory := some workspace } }
  let first ← engine.verifyOne prepared configured
  ensure "configured core workspace retains a passing result in the exact directory"
    (first.status == .pass && (← (workspace / "check-result.json").pathExists))
  let earlierInput ← IO.FS.readFile (workspace / "input.json")
  let earlierResult ← IO.FS.readFile (workspace / "check-result.json")
  let earlierLog ← IO.FS.readFile (workspace / "Generated/Checks.stdout.log")
  let second ← engine.verifyOne prepared configured
  ensure "reusing an occupied core workspace cannot overwrite earlier evidence"
    (second.status == .inconclusive && !second.reasons.isEmpty &&
     (← IO.FS.readFile (workspace / "input.json")) == earlierInput &&
     (← IO.FS.readFile (workspace / "check-result.json")) == earlierResult &&
     (← IO.FS.readFile (workspace / "Generated/Checks.stdout.log")) == earlierLog)

private def bundleFailures (temporary path : System.FilePath) : IO Unit := do
  let selected := #[identity "TxM-support"]
  let single := { request path with validators := #["alpha"] }
  let missingSource := fun id => do
    let configured ← fixtureCheck id
    if id.modelId != "TxM-support" then return .ok configured
    return .ok { configured with generate := fun target modulePrefix => do
      let plan ← configured.generate target modulePrefix
      return { plan with modules := plan.modules.map fun module =>
        { module with source := "import Formal.MissingReviewFixture\n" ++ module.source } } }
  let failed ← Run.runWith (selected.push (identity "TxM-later")) missingSource single
    (← options (temporary / "missing-source"))
  let row ← checkAt failed "samples.alpha" "TxM-support"
  ensure "source preparation failure is visible and retains the generated plan"
    (failed.finished && failed.exitCode == 2 && row.error.isSome &&
      row.result.any fun result => result.status == .inconclusive &&
        result.evidence.any (·.extension == some "lean"))
  let directory := failed.directory / checkDirectory "samples.alpha" selected[0]!
  ensure "source preparation failure never starts the check compiler"
    (!(← (directory / "Generated/Checks.attempted").pathExists))
  ensure "source and execution failures remain inspectable"
    ((← (directory / "execution.json").pathExists) &&
      (← (failed.directory / "sources/index.json").pathExists) &&
      contains (← IO.FS.readFile (failed.directory / "README.md")) "could not")
  ensure "generation and source errors display as errors" (row.displayStatus == "ERROR" && !row.timedOut)
  let later ← checkAt failed "samples.alpha" "TxM-later"
  ensure "shared-source failure prevents later checks from using a partial bundle"
    (later.error.isSome && later.result.any fun result =>
      result.status == .inconclusive && result.evidence.any (·.extension == some "lean"))
  ensure "later checks do not execute after a shared-source failure"
    (!(← (failed.directory / checkDirectory "samples.alpha" (identity "TxM-later") /
      "Generated/Checks.attempted").pathExists))
  assertSaved failed
  for blocked in #["sources", "README.md.tmp"] do
    let root := temporary / (if blocked == "sources" then "blocked-sources" else "blocked-readme")
    let loadBlocked := fun id => do
      let entries ← root.readDir
      let some directory := entries[0]? | throw (IO.userError "missing run directory")
      if blocked == "sources" then
        IO.FS.writeFile (directory.path / blocked) "source destination is blocked"
      else IO.FS.createDir (directory.path / blocked)
      load id
    let run ← Run.runWith selected loadBlocked single (← options root)
    ensure s!"{blocked} retention failure cannot appear successful" (run.exitCode == 2)
    assertSaved run

private def emptyInputChecks (temporary path : System.FilePath) : IO Unit := do
  IO.FS.writeFile path (blueprint #[])
  let emptyBlueprint ← Run.runWith registry load (request path) (← options (temporary / "empty-blueprint"))
  ensure "a blueprint without validators is an input error"
    (emptyBlueprint.exitCode == 2 && !emptyBlueprint.errors.isEmpty)
  assertSaved emptyBlueprint
  IO.FS.writeFile path sample
  let noRegistry ← Run.runWith #[] load (request path) (← options (temporary / "no-registry"))
  ensure "missing runnable registrations is an app error"
    (noRegistry.exitCode == 2 && !noRegistry.errors.isEmpty)
  assertSaved noRegistry

def run : IO Unit := do
  IO.FS.withTempDir fun temporary => do
    let path := temporary / "blueprint with spaces.json"
    IO.FS.writeFile path sample
    countsAndContinuation temporary path
    displayGuards temporary path
    preparationIsolation temporary path
    selectionChecks temporary path
    identityAndSnapshot temporary path
    outputIsolation temporary path
    storageChecks temporary path
    directDirectoryChecks temporary
    bundleFailures temporary path
    emptyInputChecks temporary path
  IO.println "App orchestration checks passed."

def compiler (args : List String) : IO UInt32 := do
  let path := System.FilePath.mk (args.getLast?.getD "")
  let source ← IO.FS.readFile path
  if let some rootArgument := args.find? (·.startsWith "--root=") then
    let directory := System.FilePath.mk (rootArgument.drop 7)
    let root := do
      let validator ← directory.parent
      let validators ← validator.parent
      validators.parent
    if let some runRoot := root then
      let index := runRoot / "run.json"
      if ← index.pathExists then
        IO.FS.writeFile (directory / "index-before-compiler.json") (← IO.FS.readFile index)
  IO.FS.writeFile (path.withExtension "attempted") "controlled compiler was invoked"
  let mode := ((source.splitOn "\n").head?.getD "").drop 3
  if mode == "log-write-error" then
    IO.FS.createDir (path.withExtension "stdout.log")
  if mode == "log-full" then
    let linked ← IO.Process.output {
      cmd := "ln", args := #["-s", "/dev/full", (path.withExtension "stdout.log").toString] }
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  if mode == "input-write-error" || mode == "manifest-write-error" then
    let some rootArgument := args.find? (·.startsWith "--root=")
      | throw (IO.userError "controlled compiler has no workspace")
    let directory := System.FilePath.mk (rootArgument.drop 7)
    if mode == "input-write-error" then
      let linked ← IO.Process.output {
        cmd := "ln", args := #["-s", "/dev/full", (directory / "input.json").toString] }
      unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    else IO.FS.createDir (directory / "execution.json")
  let falsified := mode == "falsified"
  let output ← IO.getStdout
  for line in (if mode == "support" then #[3, 4] else #[3]) do
    output.putStrLn (Json.mkObj [
      ("fileName", .str path.toString),
      ("data", .str (if falsified then "❌ Falsified" else "✅ Valid")),
      ("severity", .str (if falsified then "error" else "information")),
      ("pos", Json.mkObj [("line", toJson line), ("column", toJson (0 : Nat))])]).compress
  output.flush
  if mode == "partial" then IO.sleep 60000
  return if falsified then 1 else 0

end Workflow.Tests.Unit.App

def main (args : List String) : IO UInt32 := do
  if args == ["--version"] then
    IO.println "Controlled app compiler fixture"
    return 0
  if args.contains "--json" then Workflow.Tests.Unit.App.compiler args
  else
    Workflow.Tests.Unit.App.run
    return 0

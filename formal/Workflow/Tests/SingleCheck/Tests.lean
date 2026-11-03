import Workflow.App.Verification
import Workflow.App.Run
import Workflow.Tests.Support
import Candidates.Catalogue

namespace Workflow.Tests.SingleCheck

open Lean Workflow
open Workflow.Generator

private def ensure (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def prepared (path selector : String) : IO InputResult := do
  let preparation ← Verification.prepare path selector
  IO.ofExcept (preparation.result.mapError toString)

private def loaded (property model : String) : IO ConfiguredCheck :=
  do IO.ofExcept (← Candidates.Catalogue.loadCheck property 1 model)

private def generated (configured : ConfiguredCheck) (target : TargetDescription) : IO GenerationPlan :=
  IO.ofExcept ((generateOne configured target "Generated.SingleCheck").mapError toString)

private def theoremNames (plan : GenerationPlan) : Array String := Id.run do
  let mut names := #[]
  for module in plan.modules do
    for line in module.source.splitOn "\n" do
      if line.startsWith "theorem " then
        names := names.push (((line.drop 8).splitOn " ").head?.getD "")
  return names

private def evidenceDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  if let some input := result.evidence.find? (·.fileName == some "input.json") then
    let some directory := input.parent | throw (IO.userError "missing check evidence directory")
    return directory
  for reference in result.evidence do
    if ← reference.isDir then return reference
  throw (IO.userError "missing retained evidence directory")

private def savedResult (result : Assessor.CheckResult) : IO Json := do
  let directory ← evidenceDirectory result
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))
  ensure "saved check result matches the returned record" (json == result.toJson)
  let fields ← IO.ofExcept json.getObj?
  let names := fields.foldl (init := #[]) fun names name _ => names.push name
  ensure "check result has exactly the agreed six fields"
    (names.size == 6 && #["target", "check", "status", "reasons", "obligations", "evidence"].all names.contains)
  for reference in result.evidence do
    ensure "evidence references only retained paths" (← reference.pathExists)
  return json

private def adapterChecks : IO Unit := do
  let vault ← prepared "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
  let openTarget := { vault.target with handlers := #[] }
  for (purpose, model) in [
      ("mint", "TxM-001"), ("withdraw", "TxM-002"), ("publish", "TxM-003"),
      ("vote", "TxM-004"), ("propose", "TxM-005"), ("spend", "TxM-006")] do
    let configured ← loaded "UP-001" model
    let plan ← generated configured openTarget
    ensure s!"UP001 {model}: only the selected theorem is emitted"
      (theoremNames plan == #[s!"otherPurpose_{purpose}"] && plan.jobs.size == 1)
    ensure s!"UP001 {model}: selected metadata is attached to every obligation"
      (plan.jobs.all fun job => job.binding == some configured.context.binding &&
        job.txModelId == some model && job.role == .property && job.applicability.isNone)
  let spend ← loaded "UP-001" "TxM-006"
  let noObligations ← generated spend vault.target
  ensure "declared-purpose selection executes no source and invents no property proof"
    (noObligations.jobs.isEmpty && noObligations.modules.isEmpty &&
     noObligations.status == .noObligations && !noObligations.notes.isEmpty)

  let vesting ← prepared "Workflow/Tests/UP012/Inputs/plutus.json" "linear_vesting.linear_vesting"
  for (action, other, model) in [("claim", "cancel", "TxM-007"), ("cancel", "claim", "TxM-008")] do
    let configured ← loaded "UP-012" model
    let plan ← generated configured vesting.target
    ensure s!"UP012 {action}: source contains exactly its property and applicability theorem"
      (theoremNames plan == #[s!"dropSigner_{action}", s!"dropSigner_{action}_applies"] && plan.jobs.size == 2)
    let some main := plan.jobs.find? (·.role == .property)
      | throw (IO.userError "missing selected property")
    let some support := plan.jobs.find? (·.role == .applicability)
      | throw (IO.userError "missing selected applicability")
    ensure s!"UP012 {action}: explicit qualification uses the same exact combination"
      (main.applicability == some { moduleName := support.moduleName, name := support.name } &&
       main.binding == some configured.context.binding && support.binding == main.binding)
    let some tx := plan.modules.find? (·.name == "Generated.SingleCheck.Tx")
      | throw (IO.userError "missing selected model support")
    ensure s!"UP012 {action}: generated model aliases do not include the other action"
      ((tx.source.splitOn s!"abbrev {action} :=").length == 2 &&
       (tx.source.splitOn s!"abbrev {other} :=").length == 1)
    ensure s!"UP012 {action}: the pinned-artifact restriction also applies to single checks"
      ((generateOne configured vault.target "Generated.SingleCheck").toOption.isNone)
  for (property, version, model) in [
      ("UP-unknown", (1 : Int), "TxM-001"), ("UP-001", 2, "TxM-001"),
      ("UP-001", 1, "TxM-007"), ("UP-012", 1, "TxM-001"),
      ("UP-012", 1, "TxM-unknown")] do
    ensure "unknown property/version/model combinations cannot select executable code"
      ((← Candidates.Catalogue.loadCheck property version model).toOption.isNone)
  IO.println "Single-check adapter selection checks passed."

private def fixtureContext (modelId := "TxM-fixture") : IO CheckContext := do
  let propertyDefinition ← IO.ofExcept (PropertyDefinition.parse (Json.mkObj [
    ("identity", Json.mkObj [("id", .str "fixture"), ("definition_version", toJson (1 : Nat))])]))
  let txModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj [
    ("id", .str modelId), ("plutus_version", .str "v3"), ("description", .str "Controlled fixture model")]))
  let combinedCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str "fixture"), ("definition_version", toJson (1 : Nat))]),
    ("tx_model", .str modelId), ("limitations", .arr #[.str "Fixture-only evidence"])]))
  return { propertyDefinition, binding := { combinedCheck, txModel } }

private def fixtureJob (context : CheckContext) (name := "property") : CheckJob := {
  propertyId := "fixture"
  name
  moduleName := "Generated.Checks"
  statement := "True"
  expected := .valid
  scope := "controlled test obligation"
  txModelId := context.binding.txModel.id?
  binding := some context.binding }

private def fixturePlan (context : CheckContext) (target : TargetDescription) : GenerationPlan :=
  let support := { fixtureJob context "support" with role := .applicability }
  let main := { fixtureJob context with
    applicability := some { moduleName := support.moduleName, name := support.name } }
  { targetName := target.name
    modules := #[⟨"Generated.Checks", "-- assessment fixture\n\ntheorem property : True := by trivial\ntheorem support : True := by trivial\n"⟩]
    jobs := #[main, support]
    propertyDefinition := some context.propertyDefinition
    bindingsRequired := true }

private def observation (job : CheckJob) (observed : Executor.ObservedResult)
    (complete := true) : Executor.JobObservation :=
  { job, observed, evidenceComplete := complete }

private def execution (context : CheckContext) (jobs : Array Executor.JobObservation) : Executor.Result :=
  { state := .completed, propertyDefinition := some context.propertyDefinition, jobs }

private def assessmentChecks (target : TargetDescription) : IO Unit := do
  let context ← fixtureContext
  let plan := fixturePlan context target
  let some main := plan.jobs[0]? | throw (IO.userError "missing main fixture")
  let some support := plan.jobs[1]? | throw (IO.userError "missing support fixture")
  let assessed := fun mainResult supportResult => Assessor.assessOne target context plan
    (execution context #[observation main mainResult, observation support supportResult])
  let emptyDomain := assessed .valid .falsified
  ensure "a valid implication with falsified applicability is inconclusive"
    (emptyDomain.status == .inconclusive && emptyDomain.notRun.isNone && !emptyDomain.timedOut && emptyDomain.obligations.any
      (fun row => row.job.name == main.name && row.observed == some .valid && row.status == .inconclusive))
  ensure "a qualified falsified property fails" ((assessed .falsified .valid).status == .fail)
  ensure "a qualified valid property passes" ((assessed .valid .valid).status == .pass)
  let incomplete := Assessor.assessOne target context plan
    (execution context #[observation main .valid false, observation support .valid])
  ensure "positive markers without complete evidence cannot pass"
    (incomplete.status == .inconclusive && incomplete.obligations.any
      (fun row => row.job.name == main.name && row.observed == some .valid && !row.evidenceComplete))
  let foreign ← fixtureContext "TxM-other"
  let changed := { main with binding := some foreign.binding }
  let tampered := Assessor.assessOne target context plan
    (execution context #[observation changed .valid, observation support .valid])
  ensure "changed execution binding is inconclusive while retaining raw observations"
    (tampered.status == .inconclusive && tampered.obligations.any
      (fun row => row.job.name == main.name && row.observed == some .valid && !row.issues.isEmpty))
  let foreignSupport := { support with binding := some foreign.binding, txModelId := some "TxM-other" }
  let crossModel := { plan with jobs := #[main, foreignSupport] }
  ensure "another model's applicability cannot support this combination"
    ((context.validatePlan target crossModel).toOption.isNone &&
     (Assessor.assessOne target context crossModel
       (execution context #[observation main .valid, observation foreignSupport .valid])).status == .inconclusive)
  for malformed in [
      { plan with jobs := #[support] },
      { plan with jobs := #[{ main with applicability := none }, support] },
      { plan with jobs := #[], status := .noObligations }] do
    ensure "support-only, orphan-support, and jobless executable plans are rejected"
      ((context.validatePlan target malformed).toOption.isNone)
  let json := (assessed .falsified .valid).toJson
  let fields ← IO.ofExcept json.getObj?
  ensure "pure assessment has the six-field output contract"
    (fields.foldl (init := (0 : Nat)) (fun size _ _ => size + 1) == 6)
  IO.println "Single-check assessment integrity checks passed."

private def mockCheck (context : CheckContext) (mode := "valid") : ConfiguredCheck := {
  context
  generate := fun target modulePrefix =>
    let goal := if mode == "falsified" then "False" else "True"
    .ok {
      targetName := target.name
      modules := #[⟨s!"{modulePrefix}.Checks", s!"-- {mode}\n\ntheorem property : {goal} := by trivial\n"⟩]
      jobs := #[{ fixtureJob context with
        moduleName := s!"{modulePrefix}.Checks"
        statement := goal
        binding := none }] } }

/-- Controlled compiler protocol for coordinator tests; real solver cases run separately below. -/
def compiler (args : List String) : IO UInt32 := do
  let path := System.FilePath.mk (args.getLast?.getD "")
  let source ← IO.FS.readFile path
  IO.FS.writeFile (path.withExtension "attempted") "controlled compiler was invoked"
  let mode := ((source.splitOn "\n").head?.getD "").drop 3
  if mode == "input-write-error" || mode == "manifest-write-error" then
    let some root := args.find? (·.startsWith "--root=")
      | throw (IO.userError "controlled compiler has no output root")
    let directory := System.FilePath.mk (root.drop 7)
    if mode == "input-write-error" then
      let link ← IO.Process.output {
        cmd := "ln", args := #["-s", "/dev/full", (directory / "input.json").toString] }
      unless link.exitCode == 0 do throw (IO.userError s!"could not install full-device control: {link.stderr}")
    else IO.FS.createDir (directory / "execution.json")
  let falsified := mode == "falsified"
  let diagnostic := Json.mkObj [
    ("fileName", .str path.toString),
    ("data", .str (if falsified then "❌ Falsified" else "✅ Valid")),
    ("severity", .str (if falsified then "error" else "information")),
    ("pos", Json.mkObj [("line", toJson (3 : Nat)), ("column", toJson (0 : Nat))])]
  let output ← IO.getStdout
  output.putStrLn diagnostic.compress
  output.flush
  if mode == "partial" then IO.sleep 60000
  return if falsified then 1 else 0

private def coordinatorChecks (validSource : String) : IO Unit := do
  IO.FS.withTempDir fun temporary => do
    let path := temporary / "input with spaces.json"
    IO.FS.writeFile path "{malformed"
    let invalid ← Verification.prepare path "vault.vault"
    ensure "preparation preserves a readable invalid snapshot"
      (invalid.source == some "{malformed" && invalid.result.toOption.isNone)
    let missing ← Verification.prepare (temporary / "missing.json") "vault.vault"
    ensure "preparation invents no unavailable source"
      (missing.source.isNone && missing.result.toOption.isNone)
    IO.FS.writeFile path validSource
    let input ← prepared path.toString "vault.vault"
    IO.FS.writeFile path "changed after preparation"
    let context ← fixtureContext
    let engine : Verification.Engine := {
      options := {
        leanPath := "."
        leanCommand := (← IO.appPath).toString
        budgetMs := 5000
        outputRoot := some (temporary / "retained output") } }
    let first ← engine.verifyOne input (mockCheck context)
    ensure "the callable core can pass one complete obligation"
      (first.status == .pass && !first.timedOut && first.obligations.size == 1 && first.check == context)
    let _ ← savedResult first
    let firstDirectory ← evidenceDirectory first
    ensure "verification saves the prepared input rather than rereading its path"
      ((← IO.FS.readFile (firstDirectory / "input.json")) == validSource &&
       (← IO.FS.readFile path) == "changed after preparation")
    let second ← engine.verifyOne input (mockCheck context "falsified")
    ensure "the second verification preserves a qualified failure"
      (second.status == .fail && !second.timedOut && second.obligations.any (·.observed == some .falsified))
    let _ ← savedResult second
    let secondDirectory ← evidenceDirectory second
    ensure "separate calls cannot overwrite each other's evidence"
      (firstDirectory != secondDirectory && (← IO.FS.readFile (firstDirectory / "input.json")) == validSource)

    let timeout ← { engine with options := { engine.options with budgetMs := 500 } }.verifyOne
      input (mockCheck context "partial")
    ensure "a timed-out positive marker cannot pass"
      (timeout.status == .inconclusive && timeout.notRun.isNone && timeout.timedOut && timeout.obligations.any
        (fun row => !row.evidenceComplete && row.status == .inconclusive))
    let _ ← savedResult timeout
    let blockedResultDirectory := temporary / "timeout-retention-error"
    let timeoutRetentionEngine := { engine with options := { engine.options with
      directory := some blockedResultDirectory
      budgetMs := 500
      prepareImports := some (fun _ => do
        IO.FS.createDir (blockedResultDirectory / "check-result.json")
        pure engine.options.leanPath) } }
    let timeoutRetentionError ← timeoutRetentionEngine.verifyOne input (mockCheck context "partial")
    ensure "check-result retention failure overrides a genuine execution timeout"
      (timeoutRetentionError.status == .inconclusive && timeoutRetentionError.notRun.isNone &&
       !timeoutRetentionError.timedOut && timeoutRetentionError.reasons.any
         (fun reason => reason.startsWith "could not retain check result:"))
    let timeoutRetentionDirectory ← evidenceDirectory timeoutRetentionError
    let timeoutExecution ← IO.ofExcept (Json.parse
      (← IO.FS.readFile (timeoutRetentionDirectory / "execution.json")))
    ensure "retention failure control actually timed out during execution"
      ((timeoutExecution.getObjVal? "state").toOption == some (.str "timedOut"))

    let configured := mockCheck context
    let otherContext ← fixtureContext "TxM-other"
    let invalidIdentity : ConfiguredCheck := { configured with
      context := { context with binding := { context.binding with txModel := otherContext.binding.txModel } } }
    match generateOne invalidIdentity { input.target with plutusVersion := "v2" } "Generated" with
    | .error error => ensure "invalid metadata precedes unsupported-version classification" (error.kind == .invalidPlan)
    | .ok _ => throw (IO.userError "invalid configured metadata was accepted")
    match generateOne configured { input.target with plutusVersion := "v2" } "Generated" with
    | .error error => ensure "a valid model with an incompatible target is unsupported" (error.kind == .unsupported)
    | .ok _ => throw (IO.userError "incompatible target was accepted")
    let invalidTarget := { configured with generate := fun target modulePrefix => do
      let plan ← configured.generate target modulePrefix
      return { plan with targetName := "different.target" } }
    match generateOne invalidTarget input.target "Generated" with
    | .error error => ensure "a generator plan identity error is invalid rather than unsupported" (error.kind == .invalidPlan)
    | .ok _ => throw (IO.userError "invalid target identity was accepted")
    let invalidGenerators : Array ConfiguredCheck := #[
        { configured with generate := fun target modulePrefix => do
            let plan ← configured.generate target modulePrefix
            return { plan with targetName := "different.target" } },
        { configured with generate := fun target _ => .ok {
            targetName := target.name
            modules := #[⟨"../Escape", "theorem property : True := by trivial\n"⟩]
            jobs := #[{
              fixtureJob context with
              moduleName := "../Escape"
              binding := none }] } },
        { configured with generate := fun target modulePrefix => do
            let plan ← configured.generate target modulePrefix
            return { plan with jobs := plan.jobs.map fun job =>
              { job with txModelId := some "TxM-other", binding := some otherContext.binding } } },
        { configured with generate := fun target _ => do
            let plan := fixturePlan context target
            return { plan with jobs := plan.jobs.filter (·.role == .applicability) } },
        { configured with generate := fun target _ => do
            let plan := fixturePlan context target
            return { plan with jobs := plan.jobs.map fun job => { job with applicability := none } } },
        { configured with generate := fun target _ => do
            let plan := fixturePlan context target
            return { plan with jobs := #[] } }]
    for invalidGenerator in invalidGenerators do
      let failed ← engine.verifyOne input invalidGenerator
      ensure "generation and preparation errors return the requested check identity"
        (failed.status == .inconclusive && !failed.timedOut && failed.notRun.isNone &&
         failed.check == context && !failed.reasons.isEmpty)
      let _ ← savedResult failed
      let directory ← evidenceDirectory failed
      ensure "rejected plans create no execution or attempted compiler evidence"
        (!(← (directory / "execution.json").pathExists) &&
         !failed.evidence.any (·.extension == some "attempted"))

    let empty : ConfiguredCheck := {
      configured with
      generate := fun target _ => .ok {
        targetName := target.name
        modules := #[]
        jobs := #[]
        notes := #["empty control"] } }
    let emptyResult ← engine.verifyOne input empty
    ensure "an empty attempt is inconclusive and keeps its exact check"
      (emptyResult.status == .inconclusive && !emptyResult.timedOut && emptyResult.notRun == some .notApplicable &&
       emptyResult.obligations.isEmpty && emptyResult.check == context)
    let _ ← savedResult emptyResult
    let declared ← loaded "UP-001" "TxM-006"
    let declaredResult ← engine.verifyOne input declared
    ensure "a selected declared purpose retains its reason without executing other purposes"
      (declaredResult.status == .inconclusive && !declaredResult.timedOut && declaredResult.notRun == some .notApplicable &&
       declaredResult.obligations.isEmpty &&
       declaredResult.check == declared.context &&
       declaredResult.reasons.any (fun reason => (reason.splitOn "declared").length > 1))
    let _ ← savedResult declaredResult
    let unsupported ← loaded "UP-012" "TxM-007"
    let unsupportedResult ← engine.verifyOne input unsupported
    ensure "unsupported targets return an inconclusive record for the requested combination"
      (unsupportedResult.status == .inconclusive && !unsupportedResult.timedOut && unsupportedResult.notRun == some .unsupported &&
       unsupportedResult.obligations.isEmpty &&
       unsupportedResult.check == unsupported.context && !unsupportedResult.reasons.isEmpty)
    let _ ← savedResult unsupportedResult
    let inputWriteError ← engine.verifyOne input (mockCheck context "input-write-error")
    ensure "failed input persistence is inconclusive even when its path entry exists"
      (inputWriteError.status == .inconclusive && !inputWriteError.timedOut && inputWriteError.notRun.isNone &&
       !inputWriteError.reasons.isEmpty)
    ensure "failed snapshot paths are not advertised as retained evidence"
      (!inputWriteError.evidence.any (·.fileName == some "input.json") &&
       ((← IO.ofExcept (inputWriteError.toJson.getObjVal? "target")).getObjVal? "prepared_input").toOption == some .null)
    let _ ← savedResult inputWriteError
    let manifestWriteError ← engine.verifyOne input (mockCheck context "manifest-write-error")
    ensure "a manifest-write failure retains identity without inventing executed observations"
      (manifestWriteError.status == .inconclusive && !manifestWriteError.timedOut && manifestWriteError.notRun.isNone &&
       manifestWriteError.check == context &&
       manifestWriteError.target == input.target && manifestWriteError.obligations.isEmpty &&
       !manifestWriteError.reasons.isEmpty)
    let _ ← savedResult manifestWriteError
    let blocked := temporary / "blocked"
    IO.FS.writeFile blocked "a file, not an output directory"
    let unretained ← { engine with options := { engine.options with outputRoot := some blocked } }.verifyOne
      input configured
    ensure "unavailable evidence storage produces no false passing record"
      (unretained.status == .inconclusive && !unretained.timedOut && unretained.notRun.isNone &&
       !unretained.reasons.isEmpty && unretained.evidence.isEmpty)
    let unretainedUnsupported ←
      { engine with options := { engine.options with outputRoot := some blocked } }.verifyOne input unsupported
    ensure "unsupported classification is cleared when its record cannot be retained"
      (unretainedUnsupported.status == .inconclusive && !unretainedUnsupported.timedOut && unretainedUnsupported.notRun.isNone &&
       unretainedUnsupported.evidence.isEmpty)
    let unretainedEmpty ←
      { engine with options := { engine.options with outputRoot := some blocked } }.verifyOne input empty
    ensure "not-applicable classification is cleared when its record cannot be retained"
      (unretainedEmpty.status == .inconclusive && !unretainedEmpty.timedOut && unretainedEmpty.notRun.isNone &&
       unretainedEmpty.evidence.isEmpty)
    let occupied := temporary / "occupied"
    IO.FS.createDir occupied
    let workspaceError ←
      { engine with options := { engine.options with directory := some occupied } }.verifyOne input empty
    ensure "workspace reservation failure cannot be reported as not applicable"
      (workspaceError.status == .inconclusive && !workspaceError.timedOut && workspaceError.notRun.isNone &&
       !workspaceError.reasons.isEmpty)
  IO.println "Single-check preparation/coordinator checks passed."

private def realCase (property model blueprint selector : String) (budget : Nat)
    (status : Assessor.Status) (expectedNames : Array String) : IO Unit := do
  Workflow.Tests.Support.startCase s!"App/core: {property} / {model} / {selector}"
    s!"{status.label}; {expectedNames.size} selected obligations"
    "runWith -> captured preparation -> loadCheck -> Engine.verifyOne" budget
  let configured ← loaded property model
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  ensure "real core tests receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  let id : CheckId := { propertyId := property, definitionVersion := 1, modelId := model }
  let run ← App.Run.runWith #[id]
    (fun selected => Candidates.Catalogue.loadCheck selected.propertyId selected.definitionVersion selected.modelId)
    { path := blueprint, validators := #[selector], timeoutMs := budget }
    { executorOptions := { leanPath }, outputRoot := "output" }
  ensure "real app run finishes and stores its selected result" (run.finished && run.exitCode == 0)
  ensure "real app selection contains one validator and one exact combination"
    (run.validators.size == 1 && run.validators[0]!.name == selector &&
     run.validators[0]!.checks.size == 1 && run.validators[0]!.checks[0]!.id == id)
  let some result := run.validators[0]!.checks[0]!.result
    | throw (IO.userError "real app case has no assessed result")
  ensure "real app index matches the retained run"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  let directory ← evidenceDirectory result
  IO.println s!"CheckResult: {directory / "check-result.json"}"
  IO.println s!"Status: {result.status.label}; obligations: {result.obligations.size}"
  Workflow.Tests.Support.showCompilerLogs directory
  ensure "real single-check outcome matches its independent scenario expectation" (result.status == status)
  ensure "real single-check executes exactly the selected obligations"
    (result.obligations.map (·.job.name) == expectedNames &&
     result.obligations.all (fun row => row.job.txModelId == some model &&
       row.job.binding == some configured.context.binding && row.evidenceComplete))
  let _ ← savedResult result
  if status == .fail then
    ensure "the failing validator retains a genuine Falsified observation"
      (result.obligations.any (·.observed == some .falsified))
  else
    ensure "the passing case retains Valid observations"
      (result.obligations.all (·.observed == some .valid))

def runUnit : IO Unit := do
  adapterChecks
  let input ← prepared "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
  assessmentChecks input.target
  coordinatorChecks input.sourceText

def run : IO Unit := do
  runUnit
  realCase "UP-001" "TxM-001" "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
    120000 .pass #["otherPurpose_mint"]
  realCase "UP-001" "TxM-001" "Workflow/Tests/UP001/Inputs/plutus.json" "vault_buggy.vault_buggy"
    120000 .fail #["otherPurpose_mint"]
  realCase "UP-012" "TxM-007" "Workflow/Tests/UP012/Inputs/plutus.json" "linear_vesting.linear_vesting"
    300000 .pass #["dropSigner_claim", "dropSigner_claim_applies"]
  IO.println "Single-check core and app solver checks passed."

end Workflow.Tests.SingleCheck

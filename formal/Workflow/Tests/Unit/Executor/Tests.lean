import Workflow.Executor

open Lean Workflow
open Workflow.Executor

namespace Workflow.Tests.Unit.Executor

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def plan (mode : String) : GenerationPlan :=
  { targetName := "fixture", modules := #[⟨"Fixture.Checks",
      s!"-- {mode}\n\ntheorem fixture : True := by trivial\n"⟩]
    jobs := #[{ propertyId := "fixture", name := "fixture", moduleName := "Fixture.Checks",
                statement := "True", expected := .valid, scope := "fixture only" }] }

private def emit (path message : String) (severity := "information") (line := 3) (column := 0) : IO Unit := do
  let output ← IO.getStdout
  output.putStrLn (Json.mkObj [
    ("fileName", .str path), ("data", .str message), ("severity", .str severity),
    ("pos", Json.mkObj [("line", toJson line), ("column", toJson column)])]).compress
  output.flush

/-- The test executable also acts as a controlled compiler for isolated process tests. -/
def compiler (args : List String) : IO UInt32 := do
  let path : System.FilePath := args.getLast!
  let mode := ((← IO.FS.readFile path).splitOn "\n").head!.drop 3
  match mode with
  | "valid" => emit path.toString "✅ Valid"; return 0
  | "trace" =>
    IO.FS.writeFile (path.withExtension "invoked.json") (Json.mkObj [
      ("args", toJson args), ("cwd", .str (← IO.currentDir).toString),
      ("leanPath", (← IO.getEnv "LEAN_PATH").map Json.str |>.getD .null)]).pretty
    emit path.toString "✅ Valid"
    return 0
  | "warning" =>
    emit path.toString "declaration uses 'blasterProven' (SMT-verified, no proof term)" "warning"
    return 0
  | "falsified" =>
    emit path.toString "❌ Falsified" "error"
    emit path.toString "Counterexample:" "error"
    emit path.toString "- x: 1" "error"
    emit path.toString " - r: (Data.B\n  (ByteString.mk \"value\"))" "error"
    emit path.toString "Tactic `blaster` failed: Goal was falsified (see counterexample above)\n\n⊢ False" "error"
    return 1
  | "unexpected-valid" => emit path.toString "❌ Unexpected Valid" "error"; return 1
  | "evidence-write-error" =>
    IO.FS.createDir (path.withExtension "stderr.log")
    emit path.toString "✅ Valid"
    return 0
  | "foreign" => emit "/foreign.lean" "✅ Valid"; return 0
  | "off-range" => emit path.toString "✅ Valid" "information" 99; return 0
  | "malformed-json" =>
    emit path.toString "✅ Valid"
    (← IO.getStdout).putStrLn "{"
    return 0
  | "foreign-error" =>
    emit path.toString "✅ Valid"
    emit "/foreign.lean" "unknown identifier" "error"
    return 1
  | "error-after" | "zero-error" =>
    emit path.toString "✅ Valid"
    emit path.toString "unknown identifier 'broken'" "error"
    return if mode == "zero-error" then 0 else 1
  | "conflict" =>
    emit path.toString "✅ Valid"
    emit path.toString "❌ Falsified" "error"
    return 1
  | "wrong-detail-position" =>
    emit path.toString "❌ Falsified" "error"
    emit path.toString "Counterexample:" "error" 3 8
    return 1
  | "wrong-indented-detail-position" =>
    emit path.toString "❌ Falsified" "error"
    emit path.toString " - r: 1" "error" 3 8
    return 1
  | "orphan-detail" =>
    emit path.toString "✅ Valid"
    emit path.toString " - r: 1" "error"
    return 1
  | "sorry" | "undetermined" =>
    emit path.toString "✅ Valid"
    emit path.toString (if mode == "sorry" then "declaration uses 'sorry'" else "⚠️ Undetermined") "warning"
    return 0
  | "exit-one" => return 1
  | "delay" => IO.sleep 400; return 0
  | "late-valid" => IO.sleep 400; emit path.toString "✅ Valid"; return 0
  | "partial" => emit path.toString "✅ Valid"; IO.sleep 60000; return 0
  | "timeout" =>
    let _ ← IO.Process.spawn {
      cmd := (← IO.appPath).toString
      args := #["--child", (path.withExtension "child.pid").toString]
      stdin := .null }
    IO.sleep 60000
    return 0
  | _ => return 0

private def withResult (input : GenerationPlan) (options : Workflow.Executor.Options) (f : Result → IO Unit) : IO Unit := do
  match ← Workflow.Executor.run input options with
  | .error message => throw (IO.userError message)
  | .ok result =>
    try f result
    finally
      if let some directory := result.directory then IO.FS.removeDirAll directory

private def firstJob (result : Result) : IO JobObservation :=
  match result.jobs[0]? with
  | some value => pure value
  | none => throw (IO.userError "missing job observation")

private def boundPlan (mode : String) : IO GenerationPlan := do
  let definition ← IO.ofExcept (PropertyDefinition.parse (Json.mkObj [
    ("identity", Json.mkObj [("id", .str "fixture"), ("definition_version", toJson (1 : Nat))])]))
  let txModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj [
    ("id", .str "TxM-001"), ("title", .str "Fixture model"),
    ("plutus_version", .str "v3"), ("description", .str "One fixture context.")]))
  let combinedCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str "fixture"), ("definition_version", toJson (1 : Nat))]),
    ("tx_model", .str "TxM-001"), ("limitations", .arr #[.str "Fixture-only evidence."])]))
  let binding : CheckBinding := { txModel, combinedCheck }
  return { plan mode with
    propertyDefinition := some definition
    bindingsRequired := true
    jobs := (plan mode).jobs.map fun job =>
      { job with txModelId := some "TxM-001", binding := some binding } }

private def modelBindingChecks (options : Workflow.Executor.Options) : IO Unit := do
  for mode in ["valid", "evidence-write-error"] do
    let input ← boundPlan mode
    let some expectedJob := input.jobs[0]? | throw (IO.userError "missing bound job")
    let some expectedBinding := expectedJob.binding | throw (IO.userError "missing binding")
    withResult input options fun result => do
      let observed ← firstJob result
      check "execution retains model binding on success and file failure"
        (observed.job.binding == expectedJob.binding && observed.job.txModelId == expectedJob.txModelId &&
         result.propertyDefinition == input.propertyDefinition)
      check "retained binding does not promote incomplete evidence"
        (if mode == "valid" then result.state == .completed && observed.evidenceComplete
         else result.state == .error && !observed.evidenceComplete && observed.observed == .inconclusive)
      let some directory := result.directory | throw (IO.userError "missing bound evidence directory")
      let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
      let jobs ← IO.ofExcept ((← IO.ofExcept (manifest.getObjVal? "jobs")).getArr?)
      let some saved := jobs[0]? | throw (IO.userError "missing saved model binding")
      check "manifest preserves the exact model and combination snapshots"
        ((saved.getObjVal? "txModelId").toOption == some (.str "TxM-001") &&
         (saved.getObjVal? "transactionModel").toOption == some expectedBinding.txModel.toJson &&
         (saved.getObjVal? "combinedCheck").toOption == some expectedBinding.combinedCheck.toJson)
      let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
      let some savedModule := modules[0]? | throw (IO.userError "missing attempted module")
      check "attempted commands survive success and evidence-write failure"
        (modules.size == 1 && (savedModule.getObjVal? "invocation").toOption.any (· != .null))
      let some expectedSource := input.modules[0]? | throw (IO.userError "missing bound source")
      check "binding metadata leaves emitted Lean unchanged"
        ((← IO.FS.readFile (directory / "Fixture/Checks.lean")) == expectedSource.source)

  let valid ← boundPlan "valid"
  let some bound := valid.jobs[0]? | throw (IO.userError "missing bound fixture")
  for invalid in [
      { valid with jobs := #[{ bound with binding := none }] },
      { valid with jobs := #[{ bound with txModelId := some "TxM-002" }] },
      { valid with jobs := #[{ bound with propertyId := "other-property" }] },
      { valid with propertyDefinition := none }] do
    IO.FS.withTempDir fun directory => do
      let output := directory / "must-not-be-created"
      match ← Workflow.Executor.run invalid { options with outputRoot := some output } with
      | .error _ =>
        check "invalid bindings fail before files or processes are created" (!(← output.pathExists))
      | .ok _ => throw (IO.userError "invalid model binding reached execution")

private def commandEvidenceChecks (options : Workflow.Executor.Options) : IO Unit := do
  let expired ← Workflow.Executor.Process.run options 0 #["--must-not-run"] #[]
  check "an expired deadline invents no attempted command"
    (expired.state == .timedOut && expired.invocation.isNone)
  for controlledWrapper in [false, true] do
    IO.FS.withTempDir fun parent => do
      let options := { options with
        outputRoot := some (parent / "output with spaces")
        timeoutCommand := if controlledWrapper then options.leanCommand else options.timeoutCommand }
      withResult (plan "trace") options fun result => do
        check "trace fixture completes" (result.state == .completed)
        let some module := result.modules[0]? | throw (IO.userError "missing trace module")
        let some call := module.process.invocation | throw (IO.userError "missing attempted command")
        let actual ← IO.ofExcept (Json.parse (← IO.FS.readFile (module.path.withExtension "invoked.json")))
        let leanArgs := #["--json", s!"--root={result.directory.getD parent}", "-o",
          (module.path.withExtension "olean").toString, module.path.toString]
        check "timeout wrapper and compiler arguments are preserved without shell joining"
          (call.command == options.timeoutCommand && call.args[0]? == some "--signal=KILL" &&
           call.args[2]? == some options.leanCommand && call.args.toList.drop 3 == leanArgs.toList)
        let received := if controlledWrapper then call.args.toList else leanArgs.toList
        check "recorded arguments match the array the subprocess actually received"
          ((actual.getObjVal? "args").toOption == some (toJson received))
        check "recorded cwd matches the subprocess"
          (call.cwd == (← IO.currentDir) &&
           (actual.getObjVal? "cwd").toOption == some (.str call.cwd.toString))
        let expectedPath := s!"{result.directory.getD parent}:{options.leanPath}"
        check "explicit search-path override matches the subprocess"
          (call.environment == #[("LEAN_PATH", some expectedPath)] &&
           (actual.getObjVal? "leanPath").toOption == some (.str expectedPath))
        let some directory := result.directory | throw (IO.userError "missing trace directory")
        let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
        let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
        let some saved := modules[0]? | throw (IO.userError "missing saved trace")
        check "execution manifest retains the exact attempted invocation"
          ((saved.getObjVal? "invocation").toOption == some call.toJson)
  let unavailable ← Workflow.Executor.Process.run { options with timeoutCommand := "/missing/timeout" }
    ((← IO.monoMsNow) + 5000) #["argument with spaces"] #[("LEAN_PATH", some ".")]
  check "launch failures retain the command that was attempted"
    ((unavailable.state == .launchError ||
       (unavailable.state == .finished && unavailable.exitCode.any (· != 0))) &&
     unavailable.invocation.any (fun call => call.command == "/missing/timeout" &&
       call.args.toList.drop 3 == ["argument with spaces"]))

def run : IO Unit := do
  let options : Workflow.Executor.Options := { leanPath := ".", leanCommand := (← IO.appPath).toString, budgetMs := 5000 }
  modelBindingChecks options
  commandEvidenceChecks options
  for mode in ["valid", "warning", "falsified", "unexpected-valid"] do
    withResult (plan mode) options fun result => do
      let job ← firstJob result
      check s!"{mode}: execution completed" (result.state == .completed)
      check s!"{mode}: module evidence is complete" job.evidenceComplete
      check s!"{mode}: observed solver outcome" (job.observed ==
        if mode == "falsified" then .falsified else .valid)
      check s!"{mode}: expectation preserved" (job.job.expected == .valid)
      let some directory := result.directory | throw (IO.userError "missing evidence directory")
      check "manifest retained" (← (directory / "execution.json").pathExists)
      check "source retained" (← (directory / "Fixture/Checks.lean").pathExists)
      check "raw diagnostics retained" (← (directory / "Fixture/Checks.stdout.log").pathExists)
      let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
      let savedJobs ← IO.ofExcept ((← IO.ofExcept (manifest.getObjVal? "jobs")).getArr?)
      let some savedJob := savedJobs[0]? | throw (IO.userError "missing saved observation")
      check "manifest preserves evidence completeness"
        ((savedJob.getObjVal? "evidenceComplete").toOption == some (.bool true))
      check "manifest preserves the default property role"
        ((savedJob.getObjVal? "role").toOption == some (.str "property") &&
         (savedJob.getObjVal? "applicability").toOption == some .null)
      check "metadata-free execution does not invent model snapshots"
        ((savedJob.getObjVal? "transactionModel").toOption == some .null &&
         (savedJob.getObjVal? "combinedCheck").toOption == some .null)
  for mode in ["silent", "foreign", "off-range", "malformed-json", "foreign-error", "error-after", "zero-error", "conflict",
      "wrong-detail-position", "wrong-indented-detail-position", "orphan-detail", "sorry", "undetermined", "exit-one"] do
    withResult (plan mode) options fun result => do
      let job ← firstJob result
      check s!"{mode}: no false conclusive outcome"
        (result.state == .error && job.observed == .inconclusive && !result.problems.isEmpty)
      let complete := !["malformed-json", "foreign-error", "zero-error", "exit-one"].contains mode
      check s!"{mode}: module completeness remains independent of local issues"
        (job.evidenceComplete == complete)
  withResult (plan "valid") { options with leanCommand := "/missing/lean" } fun result => do
    let job ← firstJob result
    check "missing compiler is an execution problem" (result.state == .error && !job.evidenceComplete)
  withResult (plan "valid") { options with timeoutCommand := "/missing/timeout" } fun result => do
    let job ← firstJob result
    check "missing supervisor is an execution problem" (result.state == .error && !job.evidenceComplete)
  withResult (plan "evidence-write-error") options fun result => do
    let job ← firstJob result
    check "execution exceptions do not certify module evidence"
      (result.state == .error && job.observed == .inconclusive && !job.evidenceComplete)
  for mode in ["timeout", "partial"] do
    withResult (plan mode) { options with budgetMs := 700 } fun result => do
      let job ← firstJob result
      check s!"{mode}: bounded and inconclusive"
        (result.state == .timedOut && job.observed == .inconclusive &&
         !job.evidenceComplete && result.elapsedMs < 3000)
      if mode == "partial" then
        check "partial positive evidence retained" (job.diagnostics.any (·.message == "✅ Valid"))
      else
        let some directory := result.directory | throw (IO.userError "missing timeout evidence")
        let pid ← IO.FS.readFile (directory / "Fixture/Checks.child.pid")
        IO.sleep 30
        let process : System.FilePath := s!"/proc/{pid.trim}/status"
        if ← process.pathExists then
          let status ← IO.FS.readFile process
          check "descendant is no longer running" ((status.splitOn "State:\tZ").length > 1)
  let shared := { plan "late-valid" with modules :=
    #[⟨"Fixture.Support", "-- delay\n"⟩] ++ (plan "late-valid").modules }
  withResult shared { options with budgetMs := 700 } fun result => do
    check "budget is shared across modules" (result.state == .timedOut && result.modules.size == 2)
  let some baseJob := (plan "valid").jobs[0]? | throw (IO.userError "missing control job")
  let completedThenTimedOut : GenerationPlan := {
    targetName := "partial-module-controls"
    modules := #[
      ⟨"Fixture.First", "-- valid\n\ntheorem first : True := by trivial\n"⟩,
      ⟨"Fixture.Second", "-- partial\n\ntheorem second : True := by trivial\n"⟩,
      ⟨"Fixture.Third", "-- valid\n\ntheorem third : True := by trivial\n"⟩]
    jobs := #[
      { baseJob with name := "first", moduleName := "Fixture.First", role := .applicability },
      { baseJob with
        name := "second", moduleName := "Fixture.Second"
        applicability := some { moduleName := "Fixture.First", name := "first" } },
      { baseJob with name := "third", moduleName := "Fixture.Third" }] }
  withResult completedThenTimedOut { options with budgetMs := 700 } fun result => do
    check "later timeout retains the completed earlier module"
      (result.state == .timedOut && result.modules.size == 2 && result.jobs.size == 3)
    let some first := result.jobs[0]? | throw (IO.userError "missing completed observation")
    let some second := result.jobs[1]? | throw (IO.userError "missing timed-out observation")
    let some third := result.jobs[2]? | throw (IO.userError "missing unrun observation")
    check "completed module retains conclusive complete evidence"
      (first.observed == .valid && first.evidenceComplete && first.issues.isEmpty)
    check "timed-out module is incomplete despite its positive marker"
      (second.observed == .inconclusive && !second.evidenceComplete &&
       second.diagnostics.any (·.message == "✅ Valid"))
    check "unrun module remains incomplete" (third.observed == .inconclusive && !third.evidenceComplete)
    let some directory := result.directory | throw (IO.userError "missing partial-run evidence")
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let jobs ← IO.ofExcept ((← IO.ofExcept (manifest.getObjVal? "jobs")).getArr?)
    let some savedFirst := jobs[0]? | throw (IO.userError "missing saved applicability")
    let some savedSecond := jobs[1]? | throw (IO.userError "missing saved property")
    check "manifest preserves the applicability role"
      ((savedFirst.getObjVal? "role").toOption == some (.str "applicability"))
    check "manifest preserves the linked prerequisite"
      ((savedSecond.getObjVal? "applicability").toOption ==
        some (Json.mkObj [("module", .str "Fixture.First"), ("name", .str "first")]))
  let writeFailure := { completedThenTimedOut with modules := #[
    ⟨"Fixture.First", "-- valid\n\ntheorem first : True := by trivial\n"⟩,
    ⟨"Fixture.Second", "-- evidence-write-error\n\ntheorem second : True := by trivial\n"⟩,
    ⟨"Fixture.Third", "-- valid\n\ntheorem third : True := by trivial\n"⟩] }
  withResult writeFailure options fun result => do
    check "an evidence-write failure retains prior observations and attempted commands"
      (result.state == .error && result.modules.size == 2 &&
       result.modules.all (·.process.invocation.isSome) &&
       result.jobs.any (fun job => job.job.name == "first" && job.evidenceComplete && job.observed == .valid) &&
       result.jobs.any (fun job => job.job.name == "second" && !job.evidenceComplete && job.observed == .inconclusive) &&
       result.jobs.any (fun job => job.job.name == "third" && !job.evidenceComplete && job.observed == .inconclusive))
  IO.FS.withTempDir fun parent => do
    let root := parent / "shared output"
    let retained := { options with outputRoot := some root }
    withResult (plan "valid") retained fun first => do
      let some firstDirectory := first.directory | throw (IO.userError "missing first output directory")
      let canonicalRoot ← IO.FS.realPath root
      check "run is created beneath requested output root"
        (first.state == .completed && firstDirectory.parent == some canonicalRoot)
      let firstSource := firstDirectory / "Fixture/Checks.lean"
      let original ← IO.FS.readFile firstSource
      withResult (plan "valid") retained fun second => do
        let some secondDirectory := second.directory | throw (IO.userError "missing second output directory")
        check "separate runs keep separate directories"
          (second.state == .completed && secondDirectory.parent == some canonicalRoot &&
           secondDirectory != firstDirectory)
        check "earlier sources remain intact" ((← IO.FS.readFile firstSource) == original)
        let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (secondDirectory / "execution.json")))
        let modules ← IO.ofExcept ((← IO.ofExcept (manifest.getObjVal? "modules")).getArr?)
        let some module := modules[0]? | throw (IO.userError "missing recorded module")
        check "manifest records actual output source path"
          ((module.getObjVal? "path").toOption ==
            some (.str (secondDirectory / "Fixture/Checks.lean").toString))
    let blocked := parent / "blocked"
    IO.FS.writeFile blocked "not a directory"
    match ← Workflow.Executor.run (plan "valid") { options with outputRoot := some blocked } with
    | .error _ => pure ()
    | .ok _ => throw (IO.userError "file accepted as output root")
  let empty : GenerationPlan := { targetName := "fixture", modules := #[], jobs := #[], status := .noObligations }
  withResult empty { options with leanCommand := "/missing/lean" } fun result => do
    check "empty plan does not launch a compiler or pass" (result.state == .noObligations && result.directory.isNone)
  for invalid in [
      { plan "valid" with modules := #[⟨"../Escape", ""⟩] },
      { plan "valid" with modules := #[] },
      { plan "valid" with status := .noObligations },
      { plan "valid" with jobs := (plan "valid").jobs ++ (plan "valid").jobs },
      { plan "valid" with modules := #[⟨"Fixture.Checks", "def different := 1\n"⟩] }] do
    match ← Workflow.Executor.run invalid options with
    | .error _ => pure ()
    | .ok _ => throw (IO.userError "invalid plan accepted")
  match ← Workflow.Executor.run (plan "valid") { options with budgetMs := 0 } with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "zero budget accepted")
  IO.println "Executor fixture checks passed."

end Workflow.Tests.Unit.Executor

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--child", path] =>
    IO.FS.writeFile path (toString (← IO.Process.getPID))
    IO.sleep 60000
    return 0
  | _ =>
    if args.contains "--json" then Workflow.Tests.Unit.Executor.compiler args
    else Workflow.Tests.Unit.Executor.run *> pure 0

import Workflow.App.Run
import Workflow.Declarative.Discovery
import Workflow.Executor.Process

namespace Workflow.Declarative.Launcher

open Lean System

/-- Overrides used by isolated preparation controls; normal runs use the existing policy. -/
structure Options where
  root : FilePath := "."
  outputRoot : FilePath := "output"
  lakeCommand : String := "lake"
  timeoutCommand : String := "timeout"
  preparationBudgetMs : Option Nat := none

private structure Session where
  options : Options
  root : FilePath
  directory : FilePath
  deadline : Nat
  record : IO.Ref Json

private def save (session : Session) : IO Unit := do
  let temporary := session.directory / "index.json.tmp"
  IO.FS.writeFile temporary ((← session.record.get).pretty ++ "\n")
  IO.FS.rename temporary (session.directory / "index.json")

private def set (session : Session) (name : String) (value : Json) : IO Unit := do
  session.record.modify (·.setObjVal! name value)
  save session

private def create (options : Options) (args : List String) (budget : Nat) : IO Session := do
  let root ← IO.FS.realPath options.root
  let output := root / options.outputRoot
  IO.FS.createDirAll output
  let made ← IO.Process.output { cmd := "mktemp", args := #["-d", (output / "discovery.XXXXXXXX").toString] }
  unless made.exitCode == 0 do
    throw (IO.userError s!"could not create discovery output: {made.stderr}")
  let directory ← IO.FS.realPath made.stdout.trim
  let record ← IO.mkRef (Json.mkObj [
    ("args", toJson args), ("cwd", .str root.toString),
    ("state", .str "preparing"), ("commands", .arr #[])])
  let session := { options, root, directory, deadline := (← IO.monoMsNow) + budget, record }
  save session
  return session

private def step (session : Session) (label command : String) (args : Array String) : IO String := do
  let stdout := session.directory / (label ++ ".stdout.log")
  let stderr := session.directory / (label ++ ".stderr.log")
  let record ← session.record.get
  let previous ← IO.ofExcept do (← record.getObjVal? "commands").getArr?
  let entry := Json.mkObj [
    ("command", toJson (#[command] ++ args)), ("stdout", .str stdout.toString),
    ("stderr", .str stderr.toString), ("state", .str "running")]
  set session "commands" (.arr (previous.push entry))
  let observed ← Executor.Process.run {
    leanPath := "", leanCommand := command, timeoutCommand := session.options.timeoutCommand,
    workingDirectory := some session.root } session.deadline args #[]
  IO.FS.writeFile stdout observed.stdout
  IO.FS.writeFile stderr observed.stderr
  let state := match observed.state with
    | .finished => "finished"
    | .timedOut => "timedOut"
    | .launchError => "launchError"
  let entry := entry.setObjVal! "state" (.str state)
    |>.setObjVal! "exit_code" (observed.exitCode.map (fun n => toJson n.toNat) |>.getD .null)
    |>.setObjVal! "elapsed_ms" (toJson observed.elapsedMs)
    |>.setObjVal! "invocation" (observed.invocation.map (·.toJson) |>.getD .null)
  set session "commands" (.arr (previous.push entry))
  if observed.state == .timedOut then
    throw (IO.userError "selected-check preparation timed out")
  if observed.state == .launchError || observed.exitCode != some 0 then
    IO.eprint observed.stdout
    IO.eprint observed.stderr
    throw (IO.userError s!"{label} failed; see retained preparation logs")
  return observed.stdout

private def sourceHashes (session : Session) (properties : Array Discovery.PropertySource)
    (models : Array Discovery.ModelSource) : IO Json := do
  let sources := properties.map (·.metadataPath) ++
    properties.map (fun p => System.mkFilePath (p.definitionModule.splitOn ".") |>.withExtension "lean") ++
    properties.map (·.runPath) ++ models.map (·.path)
  if sources.isEmpty then return Json.mkObj []
  let output ← step session "source-hashes" "sha256sum"
    (#["--zero"] ++ sources.map (fun p => (session.root / p).toString))
  let hashes := output.splitOn "\x00"
  unless hashes.length == sources.size + 1 && hashes.getLast! == "" do
    throw (IO.userError "invalid source hash output")
  let mut fields := []
  for index in [:sources.size] do
    let line := hashes[index]!
    let digest := line.take 64
    let expected := "  " ++ (session.root / sources[index]!).toString
    unless digest.length == 64 && digest.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')) &&
        line.drop 64 == expected do
      throw (IO.userError "source hash output does not match the selected source")
    fields := fields ++ [(sources[index]!.toString, Json.str digest)]
  return Json.mkObj fields

private def drain (source : IO.FS.Handle) (destination : IO.FS.Stream)
    (log : IO.FS.Handle) : IO Unit := do
  repeat
    let line ← source.getLine
    if line.isEmpty then break
    log.putStr line
    log.flush
    destination.putStr line
    destination.flush

/-- Bound compilation/initialization until generated main starts, then retain app output. -/
private def launch (session : Session) (request : Workflow.App.Request) (driver marker : FilePath) : IO UInt32 := do
  let stdoutPath := session.directory / "application.stdout.log"
  let stderrPath := session.directory / "application.stderr.log"
  let args := #["env", "lean", "--run", driver.toString] ++ request.args
  let record ← session.record.get
  let previous ← IO.ofExcept do (← record.getObjVal? "commands").getArr?
  let initial := Json.mkObj [
    ("command", toJson (#[session.options.lakeCommand] ++ args)),
    ("stdout", .str stdoutPath.toString), ("stderr", .str stderrPath.toString),
    ("cwd", .str session.root.toString), ("state", .str "starting")]
  set session "commands" (.arr (previous.push initial))
  set session "state" (.str "starting")
  let stdoutFile ← IO.FS.Handle.mk stdoutPath .write
  let stderrFile ← IO.FS.Handle.mk stderrPath .write
  let child ← try
      IO.Process.spawn {
        cmd := session.options.lakeCommand, args, cwd := some session.root,
        stdin := .null, stdout := .piped, stderr := .piped, setsid := true }
    catch error =>
      set session "commands" (.arr (previous.push
        (initial.setObjVal! "state" (.str "error") |>.setObjVal! "error" (.str error.toString))))
      throw error
  let fallback : IO Unit := do
    try child.kill catch _ => pure ()
  let killGroup := do
    try
      let killed ← IO.Process.output { cmd := "/bin/kill", args := #["-KILL", "--", s!"-{child.pid}"] }
      if killed.exitCode != 0 then fallback
    catch _ => fallback
  let observedExit ← IO.mkRef (none : Option UInt32)
  try
    let output ← IO.getStdout
    let errors ← IO.getStderr
    let stdoutTask ← IO.asTask (drain child.stdout output stdoutFile) Task.Priority.dedicated
    let stderrTask ← IO.asTask (drain child.stderr errors stderrFile) Task.Priority.dedicated
    let readStart : IO (Option Nat) := do
      if !(← marker.pathExists) then return none
      let some timestamp := (← IO.FS.readFile marker).trim.toNat?
        | throw (IO.userError "application start marker has an invalid timestamp")
      return some timestamp
    let checkDrainers : IO Unit := do
      if ← IO.hasFinished stdoutTask then let _ ← IO.ofExcept stdoutTask.get; pure ()
      if ← IO.hasFinished stderrTask then let _ ← IO.ofExcept stderrTask.get; pure ()
    let mut startedAt : Option Nat := none
    let mut earlyExit : Option UInt32 := none
    let mut timedOut := false
    repeat
      checkDrainers
      if let some value ← readStart then
        startedAt := some value
        timedOut := value > session.deadline
        break
      if let some code ← child.tryWait then
        observedExit.set (some code)
        earlyExit := some code
        if let some value ← readStart then
          startedAt := some value
          timedOut := value > session.deadline
        break
      if (← IO.monoMsNow) ≥ session.deadline then
        if let some value ← readStart then
          startedAt := some value
          timedOut := value > session.deadline
        else timedOut := true
        break
      IO.sleep 10
    if timedOut then killGroup
    if !timedOut then if let some timestamp := startedAt then
      let running := initial.setObjVal! "state" (.str "running")
        |>.setObjVal! "started_at_ms" (toJson timestamp)
      set session "commands" (.arr (previous.push running))
      set session "state" (.str "running")
    let rawExit ← match earlyExit with
      | some code => pure code
      | none => do
        let mut code : Option UInt32 := none
        while code.isNone do
          checkDrainers
          code ← child.tryWait
          if code.isSome then observedExit.set code
          if code.isNone then IO.sleep 10
        pure (code.getD 2)
    -- No descendant should keep an exited owner's output pipes or resources alive.
    killGroup
    let _ ← IO.ofExcept stdoutTask.get
    let _ ← IO.ofExcept stderrTask.get
    let state := if timedOut then "timedOut" else if startedAt.isSome && rawExit == 0 then "finished" else "error"
    let exitCode : UInt32 := if state == "finished" then 0 else 2
    let finished := initial.setObjVal! "state" (.str state)
      |>.setObjVal! "raw_exit_code" (toJson rawExit.toNat)
      |>.setObjVal! "exit_code" (toJson exitCode.toNat)
      |>.setObjVal! "started_at_ms" (startedAt.map toJson |>.getD .null)
    set session "commands" (.arr (previous.push finished))
    set session "exit_code" (toJson exitCode.toNat)
    if timedOut then throw (IO.userError "application startup exhausted the selected-check preparation budget")
    if startedAt.isNone then throw (IO.userError "application process exited before its main function started")
    if rawExit != 0 then throw (IO.userError s!"application process failed (exit {rawExit}); see retained application logs")
    set session "state" (.str "finished")
    return exitCode
  catch error =>
    killGroup
    let rawExit ← match ← observedExit.get with
      | some code => pure (some code)
      | none => try some <$> child.wait catch _ => pure none
    try
      let current ← session.record.get
      let commands ← IO.ofExcept do (← current.getObjVal? "commands").getArr?
      let entry := commands.back!
      let state := if (entry.getObjValAs? String "state").toOption == some "timedOut" then "timedOut" else "error"
      let entry := entry.setObjVal! "state" (.str state)
        |>.setObjVal! "error" (.str error.toString)
        |>.setObjVal! "raw_exit_code" (rawExit.map (fun code => toJson code.toNat) |>.getD .null)
        |>.setObjVal! "exit_code" (toJson (2 : Nat))
      set session "commands" (.arr (previous.push entry))
      set session "exit_code" (toJson (2 : Nat))
    catch _ => pure ()
    throw error

private def prepare (session : Session) (request : Workflow.App.Request) : IO UInt32 := do
  let (entries, metadataErrors) ← Discovery.scan session.root
  let known := entries.foldl (fun ids entry => if ids.contains entry.id then ids else ids.push entry.id) #[]
  let source ← request.checksFile.mapM fun path => do
    let bytes ← IO.FS.readBinFile (session.root / path)
    let some text := String.fromUTF8? bytes
      | throw (IO.userError "selection file is not valid UTF-8")
    return text
  let selected ← IO.ofExcept (Discovery.select request known source)
  if request.properties.isEmpty && request.checksFile.isNone && !metadataErrors.isEmpty then
    throw (IO.userError (String.intercalate "; " metadataErrors.toList))
  if known.isEmpty then throw (IO.userError "no property Run.lean files discovered")
  let properties ← Discovery.propertiesFor session.root entries selected
  let snapshot ← source.mapM fun text => do
    let path := session.directory / "checks.json"
    IO.FS.writeFile path text
    return path
  set session "known_properties" (toJson known)
  set session "selected_properties" (toJson selected)
  set session "selection_snapshot" (snapshot.map (fun p => Json.str p.toString) |>.getD .null)
  set session "ignored_metadata_errors" (toJson metadataErrors)
  let plan := session.directory / "Plan.lean"
  IO.FS.writeFile plan (Discovery.planSource properties)
  let _ ← step session "properties-build" session.options.lakeCommand
    (#["build", "Workflow.Declarative.Discovery"] ++ Discovery.propertyModules properties)
  let planned ← step session "models-plan" session.options.lakeCommand #["env", "lean", "--run", plan.toString]
  let manifest ← IO.ofExcept (Json.parse planned)
  let ids ← IO.ofExcept do (← manifest.getObjVal? "models").getArr? >>= (·.mapM Json.getStr?)
  set session "selected_models" manifest
  let models ← Discovery.modelsFor session.root ids
  let _ ← step session "models-build" session.options.lakeCommand
    (#["build", "Workflow.Declarative.CLI"] ++ Discovery.modelModules properties models)
  let driver := session.directory / "Bootstrap.lean"
  let marker := session.directory / "app-started"
  IO.FS.writeFile driver (Discovery.bootstrap properties models known snapshot (some (session.directory / "index.json")) (some marker))
  let _ ← step session "bootstrap-check" session.options.lakeCommand
    #["env", "lean", "-o", (session.directory / "Bootstrap.olean").toString, driver.toString]
  set session "source_hashes" (← sourceHashes session properties models)
  set session "state" (.str "ready")
  launch session request driver marker

/-- Discover maintained Lean declarations and retain startup diagnostics before app execution. -/
def runWith (options : Options) (args : List String) : IO UInt32 := do
  match Workflow.App.parseRequest args with
  | .error message => IO.eprintln s!"{message}\nUsage: {Workflow.App.Run.usage}"; return 2
  | .ok request =>
    let current ← IO.mkRef (none : Option Session)
    try
      let budget := options.preparationBudgetMs.getD (max request.timeoutMs 30000)
      let session ← create options args budget
      current.set (some session)
      return ← prepare session request
    catch error =>
      if let some session ← current.get then
        try
          set session "state" (.str "failed")
          set session "error" (.str error.toString)
        catch _ => pure ()
        try IO.eprintln s!"Could not prepare selected checks: {error}\nPreparation evidence: {session.directory / "index.json"}"
        catch _ => pure ()
      else
        try IO.eprintln s!"Could not prepare selected checks: {error}"
        catch _ => pure ()
      return (2 : UInt32)

def run (args : List String) : IO UInt32 := runWith {} args

end Workflow.Declarative.Launcher

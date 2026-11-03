import Lean.Data.Json
import Workflow.Tests.Logging

namespace Workflow.Tests.Support

open Lean

def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

def stringField (value : Json) (key : String) : IO String :=
  IO.ofExcept do (← value.getObjVal? key).getStr?

def rows (report : Json) : IO (Array Json) :=
  IO.ofExcept do (← report.getObjVal? "checks").getArr?

structure CLIRun where
  exitCode : UInt32
  report : Json
  directory : System.FilePath
  input : String

def startCase (label expected command : String) (budgetMs : Nat) : IO Unit := do
  Logging.line s!"\n=== START: {label} ==="
  Logging.line s!"Command: {command}"
  Logging.line s!"Execution budget: {budgetMs} ms"
  unless expected.isEmpty do Logging.line s!"Expected: {expected}"

def showCompilerLogs (directory : System.FilePath) : IO Unit := do
  let manifestPath := directory / "execution.json"
  unless (← manifestPath.pathExists) do
    Logging.line "Compiler logs: no execution manifest for this report."
    return ()
  let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile manifestPath))
  let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
  if modules.isEmpty then Logging.line "Compiler logs: no module entries in the execution manifest."
  for item in modules do
    let source := System.FilePath.mk (← stringField item "path")
    for extension in #["stdout.log", "stderr.log"] do
      let path := source.withExtension extension
      let output ← if extension == "stderr.log" then IO.getStderr else IO.getStdout
      output.putStrLn s!"\n--- Compiler log: {path} ---"
      if ← path.pathExists then
        let contents ← IO.FS.readFile path
        if contents.isEmpty then output.putStrLn "(empty)"
        else
          output.putStr contents
          unless contents.endsWith "\n" do output.putStrLn ""
      else output.putStrLn "(file missing)"
      output.flush

def invoke (blueprint selector : String) (checkId : Option String) (budgetMs : Nat)
    (label := "CLI workflow") (expected := "") : IO CLIRun := do
  let selection := checkId.map (fun id => #["--check", id]) |>.getD #[]
  let arguments := #["exe", "universal", blueprint, selector] ++ selection ++
    #["--timeout-ms", toString budgetMs]
  startCase label expected ("lake " ++ String.intercalate " " arguments.toList) budgetMs
  let original ← IO.FS.readFile blueprint
  let output ← Logging.run {
    cmd := "lake"
    args := arguments }
  let some reportLine := (output.stdout.splitOn "\n").find? (·.startsWith "Report: ")
    | throw (IO.userError s!"CLI did not save a report (exit {output.exitCode}); see streamed output above.")
  let reportPath := System.FilePath.mk ((reportLine.drop 8).trim)
  let report ← IO.ofExcept (Json.parse (← IO.FS.readFile reportPath))
  let some directory := reportPath.parent | throw (IO.userError "missing report directory")
  showCompilerLogs directory
  check "CLI preserves the supplied input" ((← IO.FS.readFile blueprint) == original)
  let root ← IO.FS.realPath "output"
  check "CLI uses the local output folder" (directory.parent == some root)
  check "plain report exists" (← (directory / "report.txt").pathExists)
  check "report points to its actual output directory"
    ((← stringField report "evidenceDirectory") == directory.toString)
  check "readable CLI input is retained for every outcome"
    ((← IO.FS.readFile (directory / "input.json")) == original)
  let invocation ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "invocation.json")))
  let requestArgs := #[blueprint, selector] ++ selection ++ #["--timeout-ms", toString budgetMs]
  let cwd ← IO.currentDir
  let inputPath := System.FilePath.mk blueprint
  let inputPath := if inputPath.isAbsolute then inputPath else cwd / inputPath
  check "CLI invocation preserves the arguments, effective paths, and settings"
    ((invocation.getObjVal? "args").toOption == some (Lean.toJson requestArgs) &&
     (invocation.getObjVal? "cwd").toOption == some (.str cwd.toString) &&
     (invocation.getObjVal? "inputPath").toOption == some (.str inputPath.toString) &&
     (invocation.getObjVal? "validator").toOption == some (.str selector) &&
     (invocation.getObjVal? "requestedCheck").toOption == some (checkId.map Json.str |>.getD .null) &&
     (invocation.getObjVal? "timeoutMs").toOption == some (Lean.toJson budgetMs))
  let resolved := do
    let definition ← (report.getObjVal? "propertyDefinition").toOption
    let identity ← (definition.getObjVal? "identity").toOption
    (identity.getObjVal? "id").toOption
  check "CLI invocation records the property resolved by the catalogue"
    ((invocation.getObjVal? "resolvedCheck").toOption == some (resolved.getD .null))
  return { exitCode := output.exitCode, report, directory, input := original }

def expectOutcome (label : String) (run : CLIRun) (status : String) (exitCode : UInt32) : IO Unit := do
  let savedExit ← IO.ofExcept do (← run.report.getObjVal? "exitCode").getNat?
  check s!"{label}: process exit code" (run.exitCode == exitCode)
  check s!"{label}: report exit code" (savedExit == exitCode.toNat)
  check s!"{label}: report status" ((← stringField run.report "status") == status)

def expectPropertyDefinition (label : String) (run : CLIRun)
    (propertyId : String) (definitionVersion : Nat) (primary : String) : IO Unit := do
  let definition ← IO.ofExcept (run.report.getObjVal? "propertyDefinition")
  let identity ← IO.ofExcept (definition.getObjVal? "identity")
  let version ← IO.ofExcept do (← identity.getObjVal? "definition_version").getNat?
  let formalization ← IO.ofExcept (definition.getObjVal? "formalization")
  check s!"{label}: property definition identity" ((← stringField identity "id") == propertyId)
  check s!"{label}: property definition version" (version == definitionVersion)
  check s!"{label}: property definition primary" ((← stringField formalization "primary") == primary)
  let manifestPath := run.directory / "execution.json"
  if ← manifestPath.pathExists then
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile manifestPath))
    check s!"{label}: report and execution retain the same property definition"
      ((manifest.getObjVal? "propertyDefinition").toOption == some definition)

def expectBindings (label : String) (run : CLIRun)
    (propertyId : String) (definitionVersion : Nat)
    (expected : Array (String × String)) : IO Unit := do
  let checks ← rows run.report
  let names ← checks.mapM (fun row => stringField row "name")
  check s!"{label}: exact bound job selection" (names == expected.map Prod.fst)
  let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "execution.json")))
  let jobs ← IO.ofExcept do (← manifest.getObjVal? "jobs").getArr?
  check s!"{label}: execution retains every requested job" (jobs.size == checks.size)
  for (name, modelId) in expected do
    let matching := checks.filter fun row => (row.getObjVal? "name").toOption == some (.str name)
    check s!"{label}: unique report row for {name}" (matching.size == 1)
    let some row := matching[0]? | throw (IO.userError s!"missing report row: {name}")
    let model ← IO.ofExcept (row.getObjVal? "transactionModel")
    let combined ← IO.ofExcept (row.getObjVal? "combinedCheck")
    let property ← IO.ofExcept (combined.getObjVal? "property")
    let version ← IO.ofExcept do (← property.getObjVal? "definition_version").getNat?
    check s!"{label}: registered model for {name}" ((← stringField row "txModelId") == modelId)
    check s!"{label}: model snapshot identity for {name}" ((← stringField model "id") == modelId)
    check s!"{label}: model context format for {name}" ((← stringField model "plutus_version") == "v3")
    check s!"{label}: combined model reference for {name}" ((← stringField combined "tx_model") == modelId)
    check s!"{label}: combined property reference for {name}"
      ((← stringField property "id") == propertyId && version == definitionVersion)
    let moduleName ← stringField row "module"
    let observations := jobs.filter fun item =>
      (item.getObjVal? "name").toOption == some (.str name) &&
      (item.getObjVal? "module").toOption == some (.str moduleName)
    check s!"{label}: unique execution observation for {name}" (observations.size == 1)
    let some observation := observations[0]?
      | throw (IO.userError s!"missing execution observation: {name}")
    for field in #["txModelId", "transactionModel", "combinedCheck", "statement"] do
      check s!"{label}: exact {field} snapshot retained for {name}"
        ((observation.getObjVal? field).toOption == (row.getObjVal? field).toOption)

def expectRows (label : String) (run : CLIRun) (count : Nat)
    (property status observed bound : String) : IO Unit := do
  let checks ← rows run.report
  check s!"{label}: requested obligation count" (checks.size == count)
  for row in checks do
    check s!"{label}: property identity" ((← stringField row "property") == property)
    check s!"{label}: row status" ((← stringField row "status") == status)
    check s!"{label}: raw observation" ((← stringField row "observed") == observed)
    check s!"{label}: stated bound" (((← stringField row "scope").splitOn bound).length > 1)

def expectProblem (label : String) (run : CLIRun) (fragment : String) : IO Unit := do
  let problems ← IO.ofExcept do (← run.report.getObjVal? "problems").getArr?
  check label (problems.any fun item =>
    (((item.getStr?).toOption.getD "").splitOn fragment).length > 1)

def expectArtifacts (label : String) (run : CLIRun) (sources : Array String) : IO Unit := do
  check s!"{label}: exact input snapshot" ((← IO.FS.readFile (run.directory / "input.json")) == run.input)
  for source in sources do
    check s!"{label}: retained {source}" (← (run.directory / "Generated" / source).pathExists)
  let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "execution.json")))
  let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
  for item in modules do
    let path := System.FilePath.mk (← stringField item "path")
    check s!"{label}: recorded module location" (path.parent == some (run.directory / "Generated"))
    check s!"{label}: recorded module exists" (← path.pathExists)
    check s!"{label}: compiler stdout retained" (← (path.withExtension "stdout.log").pathExists)
    check s!"{label}: compiler stderr retained" (← (path.withExtension "stderr.log").pathExists)
    let call ← IO.ofExcept (item.getObjVal? "invocation")
    if call == .null then
      check s!"{label}: unattempted modules have no process exit code"
        ((item.getObjVal? "exitCode").toOption == some .null &&
         (item.getObjVal? "timedOut").toOption == some (.bool true))
    else
      let args ← IO.ofExcept do (← call.getObjVal? "args").getArr?
      check s!"{label}: records the actual timeout and Lean argument array"
        ((← stringField call "command") == (← stringField manifest "timeoutCommand") &&
         args[0]? == some (.str "--signal=KILL") &&
         args[2]? == some (.str (← stringField manifest "leanCommand")) &&
         args.toList.drop 3 == [.str "--json", .str s!"--root={run.directory}", .str "-o",
           .str (path.withExtension "olean").toString, .str path.toString])

end Workflow.Tests.Support

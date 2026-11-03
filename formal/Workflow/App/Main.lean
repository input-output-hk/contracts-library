import Workflow

namespace Workflow.Main

open Lean

private def usage : String :=
  "usage: plutus-upv run BLUEPRINT VALIDATOR [--check PROPERTY_ID] [--timeout-ms MILLISECONDS]"

private def outputRoot : System.FilePath := "output"

private structure Request where
  path : System.FilePath
  selector : String
  checkId : Option String := none
  budgetMs : Nat := 300000

private structure Invocation where
  args : List String
  cwd : System.FilePath
  request : Option Request := none
  resolvedCheck : Option String := none

private def Invocation.toJson (invocation : Invocation) : Json :=
  let inputPath := invocation.request.map fun request =>
    if request.path.isAbsolute then request.path else invocation.cwd / request.path
  Json.mkObj [
    ("args", Lean.toJson invocation.args), ("cwd", .str invocation.cwd.toString),
    ("inputPath", inputPath.map (fun path => Json.str path.toString) |>.getD .null),
    ("validator", invocation.request.map (fun request => Json.str request.selector) |>.getD .null),
    ("requestedCheck", (invocation.request.bind (·.checkId)).map Json.str |>.getD .null),
    ("resolvedCheck", invocation.resolvedCheck.map Json.str |>.getD .null),
    ("timeoutMs", invocation.request.map (fun request => Lean.toJson request.budgetMs) |>.getD .null)]

private def parseOptions : List String → Request → Except String Request
  | [], request => .ok request
  | "--check" :: id :: rest, request => parseOptions rest { request with checkId := some id }
  | "--timeout-ms" :: value :: rest, request => do
    let some budget := value.toNat? | throw "timeout must be positive milliseconds"
    if budget == 0 then throw "timeout must be positive milliseconds"
    parseOptions rest { request with budgetMs := budget }
  | _, _ => .error usage

private def finish (report : Reporter.Report) (invocation : Invocation)
    (source : Option String := none) : IO UInt32 := do
  try
    let directory ← match report.evidenceDirectory with
      | some value => pure value
      | none => Executor.createRunDirectory (some outputRoot)
    let report := { report with evidenceDirectory := some directory }
    IO.FS.writeFile (directory / "invocation.json") (invocation.toJson.pretty ++ "\n")
    if let some original := source then IO.FS.writeFile (directory / "input.json") original
    report.write directory
    IO.print report.text
    IO.println s!"Report: {directory / "report.json"}"
    return report.exitCode
  catch error =>
    IO.eprintln s!"INCONCLUSIVE: could not save the report: {error}"
    return 2

private def runRequest (resolveProvider : Option String → IO (Except String Generator.Provider))
    (request : Request) (invocation : Invocation) : IO UInt32 := do
  let (source, inputResult) ← Input.readWithSource request.path request.selector
  let providerResult ← resolveProvider request.checkId
  let invocation := { invocation with resolvedCheck := providerResult.toOption.map (·.id) }
  let definition := providerResult.toOption.bind (·.propertyDefinition)
  let input ← match inputResult with
    | .ok value => pure value
    | .error error => return ← finish (Reporter.failure request.selector (toString error) definition) invocation source
  let provider ← match providerResult with
    | .ok value => pure value
    | .error message => return ← finish (Reporter.failure input.target.name message) invocation source
  let plan ← match Generator.generate provider input.target "Generated" with
    | .ok value => pure value
    | .error error => return ← finish (Reporter.failure input.target.name (toString error) definition) invocation source
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  let result ← match ← Executor.run plan {
      leanPath, budgetMs := request.budgetMs, outputRoot := some outputRoot } with
    | .ok value => pure value
    | .error message => return ← finish (Reporter.failure input.target.name message definition) invocation source
  finish (Reporter.build plan result) invocation source

def run (resolveProvider : Option String → IO (Except String Generator.Provider))
    (args : List String) : IO UInt32 := do
  let invocation : Invocation := { args, cwd := ← IO.currentDir }
  match args with
  | ["--help"] => IO.println usage; return 0
  | path :: selector :: rest =>
    match parseOptions rest { path, selector } with
    | .error message => finish (Reporter.failure selector message) invocation
    | .ok request => runRequest resolveProvider request { invocation with request := some request }
  | _ => finish (Reporter.failure "unselected" usage) invocation

end Workflow.Main

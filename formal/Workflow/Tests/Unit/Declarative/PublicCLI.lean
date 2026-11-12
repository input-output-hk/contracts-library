import Lean.Data.Json
import Workflow.Tests.Support

namespace Workflow.Tests.Unit.Declarative.PublicCLI

open Lean System
open Workflow.Tests.Support (check stringField)

private def has (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def json (path : FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def array (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept do (← value.getObjVal? name).getArr?

private def createEvidence (root : FilePath) : IO FilePath := do
  IO.FS.createDirAll (root / "output")
  let output ← IO.Process.output {
    cmd := "mktemp", args := #["-d", (root / "output/public-cli.XXXXXXXX").toString] }
  check "public test evidence directory created" (output.exitCode == 0)
  IO.FS.realPath output.stdout.trim

private def invoke (root evidence : FilePath) (label : String) (args : Array String)
    (expected : UInt32 := 0) (caller : Option FilePath := none) : IO IO.Process.Output := do
  Workflow.Tests.Logging.line s!"Public CLI: {label}; expected process exit {expected}"
  let output ← Workflow.Tests.Logging.run {
    cmd := "timeout"
    args := #["--signal=KILL", "180s", "/bin/bash", (root / "plutus-upv").toString] ++ args
    cwd := some (caller.getD root), setsid := true }
    (some (evidence / (label ++ ".stdout.log")))
    (some (evidence / (label ++ ".stderr.log")))
  check s!"{label}: expected process exit" (output.exitCode == expected)
  return output

private def outputRun (result : IO.Process.Output) : IO (FilePath × Json × Array Json) := do
  let locations := (result.stdout.splitOn "\n").filter (·.startsWith "Output: ")
  check "app publishes one output location" (locations.length == 1)
  let directory := FilePath.mk ((locations[0]!.drop 8).trim)
  let index ← json (directory / "run.json")
  check "app finishes and retains no orchestration errors"
    ((index.getObjValAs? Bool "finished").toOption == some true &&
      (← array index "errors").isEmpty)
  let options ← IO.ofExcept (index.getObjVal? "options")
  check "run points to the retained discovery snapshot"
    ((options.getObjValAs? String "discovery_snapshot").toOption == some "discovery.json" &&
      (← (directory / "discovery.json").pathExists))
  let mut results := #[]
  for validator in ← array index "validators" do
    for checkEntry in ← array validator "checks" do
      check "selected check has no orchestration error"
        ((checkEntry.getObjVal? "error").toOption == some .null)
      let path ← stringField checkEntry "result"
      results := results.push (← json (directory / path))
  return (directory, index, results)

private def counts (result : IO.Process.Output) (validator : String) (expected : List String) : IO Unit := do
  let lines := result.stdout.splitOn "\n"
  let matching := lines.filter fun line =>
    ((line.splitOn " ").filter (!·.isEmpty)).head? == some validator
  check "validator has one terminal summary row" (matching.length == 1)
  let fields := (matching[0]!.splitOn " ").filter (!·.isEmpty)
  check "terminal categories preserve expected counts" (fields.drop 1 == expected)

private def emptyAndCaller (root evidence : FilePath) : IO Unit := do
  let switches := evidence / "all disabled.json"
  IO.FS.writeFile switches "{\"UP-000\":false,\"UP-001\":false,\"UP-004\":false,\"UP-007\":false,\"UP-008\":false,\"UP-011\":false,\"UP-012\":false,\"UP-013\":false,\"UP-014\":false,\"UP-015\":false}"
  let unsupported := root / "Workflow/Tests/UP012/Inputs/unsupported.json"
  let empty ← invoke root evidence "empty-selection"
    #["run", unsupported.toString, "--checks-file", switches.toString]
  let (directory, _, results) ← outputRun empty
  check "all disabled is an explicit no-op with no passing checks"
    (results.isEmpty && has empty.stdout "No checks selected")
  check "empty selection preserves the original switch file"
    ((← IO.FS.readBinFile (directory / "checks.json")) == (← IO.FS.readBinFile switches))
  let caller := evidence / "caller with spaces"
  IO.FS.createDirAll caller
  IO.FS.writeBinFile (caller / "plutus.json") (← IO.FS.readBinFile unsupported)
  let source := "{\r\n\"UP-000\":false,\"UP-001\":false,\"UP-004\":false,\"UP-007\":false,\"UP-008\":false,\"UP-011\":false,\"UP-012\":false,\"UP-013\":false,\"UP-014\":false,\"UP-015\":true\r\n}\r\n"
  IO.FS.writeFile (caller / "my checks.json") source
  let invoked ← invoke root evidence "caller-paths"
    #["run", "--checks-file", "my checks.json"] 0 (some caller)
  let (saved, index, selected) ← outputRun invoked
  check "caller selection retains only the enabled property" (selected.size == 1)
  check "CRLF switch bytes survive planning and execution"
    ((← IO.FS.readBinFile (saved / "checks.json")) == source.toUTF8)
  let options ← IO.ofExcept (index.getObjVal? "options")
  check "caller-relative blueprint and selection paths are preserved"
    ((options.getObjValAs? String "blueprint").toOption == some (caller / "plutus.json").toString &&
      (options.getObjValAs? String "selection_file").toOption == some (caller / "my checks.json").toString)
  counts invoked "unsupported.validator" ["0", "0", "1", "0", "0"]

private def defaultSelection (root evidence : FilePath) : IO Unit := do
  let input ← json (root / "Workflow/Tests/UP001/Inputs/plutus.json")
  let validators ← array input "validators"
  let selected := validators.filter fun entry =>
    (entry.getObjValAs? String "title").toOption.any (·.startsWith "vault.vault.")
  check "default selection fixture retains a known compiled target" (!selected.isEmpty)
  let parameter := Json.mkObj [("title", .str "testParameter"),
    ("schema", Json.mkObj [("dataType", .str "bytes")])]
  let prepared := selected.map (·.setObjVal! "parameters" (.arr #[parameter]))
  let path := evidence / "unapplied parameter.json"
  IO.FS.writeFile path ((input.setObjVal! "validators" (.arr prepared)).pretty ++ "\n")
  let result ← invoke root evidence "default-selection" #["run", path.toString]
  let (_, _, results) ← outputRun result
  check "default discovery keeps all twenty current combinations"
    (results.size == 20 && results.all fun checkResult =>
      (checkResult.getObjValAs? String "status").toOption == some "INCONCLUSIVE" &&
      (checkResult.getObjVal? "obligations" >>= Json.getArr?).toOption.any (·.isEmpty))
  counts result "vault.vault" ["0", "0", "20", "0", "0"]

private def declaredPurposes (root evidence : FilePath) : IO Unit := do
  let input ← json (root / "Workflow/Tests/UP012/Inputs/reusable.json")
  let validators ← array input "validators"
  let some original := validators.find? fun entry =>
    (entry.getObjValAs? String "title").toOption == some "never_accept.never_accept.spend"
    | throw (IO.userError "missing always-rejecting fixture")
  let purposes := #["spend", "mint", "withdraw", "publish", "vote", "propose"]
  let variants := purposes.map fun purpose =>
    original.setObjVal! "title" (.str ("never_accept.never_accept." ++ purpose))
  let path := evidence / "all declared purposes.json"
  IO.FS.writeFile path ((input.setObjVal! "validators" (.arr variants)).pretty ++ "\n")
  let result ← invoke root evidence "all-declared-purposes" #["run", path.toString, "--check", "UP-001"]
  let (directory, index, results) ← outputRun result
  check "all declared purposes retain six skipped combinations without obligations"
    (results.size == 6 && results.all fun item =>
      (item.getObjVal? "obligations" >>= Json.getArr?).toOption.any (·.isEmpty))
  let entries ← array (← array index "validators")[0]! "checks"
  check "declared-purpose skips retain the not-applicable reason"
    (entries.all fun entry => (entry.getObjValAs? String "not_run").toOption == some "not_applicable")
  for entry in entries do
    let resultPath := directory / (← stringField entry "result")
    let some parent := resultPath.parent | throw (IO.userError "missing result directory")
    check "declared-purpose skip does not execute the solver"
      (!(← (parent / "execution.json").pathExists))
  counts result "never_accept.never_accept" ["0", "0", "6", "0", "0"]

def run : IO Unit := do
  let root ← IO.FS.realPath "."
  let evidence ← createEvidence root
  Workflow.Tests.Logging.line s!"Public CLI test evidence: {evidence}"
  let help ← invoke root evidence "help" #["--help"]
  check "public help preserves the product command" (has help.stdout "Plutus UPV")
  let _ ← invoke root evidence "invalid-usage" #["run", "--timeout-ms", "0"] 2
  emptyAndCaller root evidence
  defaultSelection root evidence
  declaredPurposes root evidence
  IO.println "Lean public CLI smoke checks passed."

end Workflow.Tests.Unit.Declarative.PublicCLI

def main : IO Unit := Workflow.Tests.Unit.Declarative.PublicCLI.run

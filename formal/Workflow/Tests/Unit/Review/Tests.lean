import Workflow.App.Review

namespace Workflow.Tests.Unit.Review

open Lean Workflow Workflow.App

private def ensure (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def contains (text fragment : String) : Bool := (text.splitOn fragment).length > 1

private def id (model : String) : CheckId :=
  { propertyId := "UP-fixture", definitionVersion := 1, modelId := model }

private def put (directory : System.FilePath) (relative : System.FilePath) : IO Unit := do
  let path := directory / relative
  if let some parent := path.parent then IO.FS.createDirAll parent
  IO.FS.writeFile path "fixture\n"

private def command (cmd : String) (args : Array String) : IO Unit := do
  let output ← IO.Process.output { cmd, args }
  ensure s!"{cmd} succeeded: {output.stderr}" (output.exitCode == 0)

private def assessment (model := "TxM-one") : IO Assessor.CheckResult := do
  let propertyDefinition ← IO.ofExcept (PropertyDefinition.parse (Json.mkObj [
    ("identity", Json.mkObj [("id", .str "UP-fixture"), ("definition_version", toJson (1 : Nat))])]))
  let txModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj [
    ("id", .str model), ("plutus_version", .str "v3")]))
  let combinedCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj [("id", .str "UP-fixture"), ("definition_version", toJson (1 : Nat))]),
    ("tx_model", .str model)]))
  return {
    target := {
      name := "fixture", plutusVersion := "v3", compiledCode := ""
      handlers := #[], parameters := none, definitions := none, compiler := none }
    check := { propertyDefinition, binding := { combinedCheck, txModel } }
    status := .inconclusive
    reasons := #["Controlled [reason]: unsupported model <shape>."]
    obligations := #[] }

private def hex (c : Char) : Nat :=
  if c >= '0' && c <= '9' then c.toNat - '0'.toNat else c.toNat - 'A'.toNat + 10

private def decodeBytes : List Char → List UInt8
  | '%' :: a :: b :: rest => UInt8.ofNat (hex a * 16 + hex b) :: decodeBytes rest
  | c :: rest => UInt8.ofNat c.toNat :: decodeBytes rest
  | [] => []

private def linksResolve (directory : System.FilePath) : IO Unit := do
  let page ← IO.FS.readFile (directory / "README.md")
  let links := (page.splitOn "](").drop 1
  ensure "review page contains links" (!links.isEmpty)
  let root ← IO.FS.realPath directory
  for part in links do
    let encoded := (part.splitOn ")").head!
    let decoded := String.fromUTF8! ⟨(decodeBytes encoded.toList).toArray⟩
    let relative := System.FilePath.mk decoded
    ensure "review links are relative" (!relative.isAbsolute)
    let path := directory / relative
    ensure "review links reach ordinary retained files" ((← path.symlinkMetadata).type == .file)
    let resolved ← IO.FS.realPath path
    ensure "review links stay in the copied bundle"
      (resolved.toString.startsWith (root.toString ++ "/"))

def run : IO Unit := do
  IO.FS.withTempDir fun temporary => do
    let directory := temporary / "original"
    IO.FS.createDir directory
    let name := "name [a](b)% #é"
    let first := checkDirectory name (id "TxM-one")
    let second := checkDirectory name (id "TxM-two")
    let missing := checkDirectory "broken" (id "TxM-missing")
    for path in #["input.json", "run.json", "checks.json", "sources/index.json",
        "sources/Workflow/Definitions.lean", "sources/_logs/revision.stdout",
        "sources/_logs/revision.stderr", "sources/_logs/revision.command.json",
        "sources/_logs/revision.result.json", "sources/lean-toolchain",
        "sources/lake-manifest.json"] do
      put directory path
    for path in #[first / "Generated/Validator.lean", first / "Generated/Checks.lean",
        first / "Generated/Tx.lean", first / "Generated/Checks.stdout.log",
        first / "execution.json", first / "input.json", first / "check-result.json",
        second / "Generated/Checks.lean", second / "execution.json"] do
      put directory path
    let run : RunRecord := {
      directory, input := some "input.json"
      validators := #[
        { name, checks := #[
          { id := id "TxM-one", resultFile := some (first / "check-result.json"),
            result := some (← assessment) },
          { id := id "TxM-two", error := some "result retention failed" },
          { id := id "TxM-unsupported", result := some (← assessment "TxM-unsupported") },
          { id := id "TxM-catalogue", error := some "catalogue entry missing" },
          { id := id "TxM-pending" }] },
        { name := "broken", preparationError := some "invalid blueprint",
          checks := #[{ id := id "TxM-missing" }] }] }
    Review.write run
    let page ← IO.FS.readFile (directory / "README.md")
    ensure "every selected check appears, including preparation failures"
      (#["TxM-one", "TxM-two", "TxM-unsupported", "TxM-catalogue", "TxM-pending",
        "TxM-missing"].all (contains page))
    ensure "all generated modules including optional Tx are linked"
      (contains page "Generated/Validator.lean](" && contains page "Generated/Tx.lean](" &&
        (page.splitOn "Generated/Checks.lean](").length == 3)
    ensure "missing generated files have explanations rather than fabricated links"
      (contains page "No generated Lean is retained" && contains page "catalogue entry missing" &&
        contains page "invalid blueprint" && contains page "Pending:" &&
        !contains page (missing.toString ++ "/Generated"))
    ensure "recorded verdict and reasons survive without a new overall verdict"
      (contains page "**INCONCLUSIVE**" && contains page "Controlled \\[reason\\]" &&
        !contains page "Overall")
    ensure "labels escape Markdown and links escape literal percent and UTF-8 bytes"
      (contains page "name \\[a\\]\\(b\\)%" && contains page "%25" &&
        contains page "%25C3%25A9")
    ensure "shared Lean sources are linked once per run"
      ((page.splitOn "sources/Workflow/Definitions.lean](").length == 2 &&
        contains page "sources/index.json](")
    ensure "source capture logs and pinned build metadata are linked"
      (#["revision.stdout", "revision.stderr", "revision.command.json", "revision.result.json",
        "sources/lean-toolchain", "sources/lake-manifest.json"].all (contains page))
    linksResolve directory
    let copied := temporary / "copied"
    command "cp" #["-R", directory.toString, copied.toString]
    linksResolve copied
    IO.FS.removeFile (directory / first / "Generated/Tx.lean")
    IO.FS.removeFile (directory / first / "check-result.json")
    IO.FS.removeFile (directory / "input.json")
    put temporary "external/Secret.lean"
    command "ln" #["-s", (temporary / "external").toString,
      (directory / second / "Escaped").toString]
    command "ln" #["-s", (temporary / "external/Secret.lean").toString,
      (directory / first / "Generated/Symlink.lean").toString]
    Review.write run
    let retained ← IO.FS.readFile (directory / "README.md")
    ensure "removed files and symbolic links never receive links"
      (!contains retained "Generated/Tx.lean](" && !contains retained "Secret.lean" &&
        !contains retained "Symlink.lean" && !contains retained "/check-result.json](" &&
        !contains retained "](input.json)")
    linksResolve directory
  IO.println "Run review index checks passed."

end Workflow.Tests.Unit.Review

def main : IO Unit := Workflow.Tests.Unit.Review.run

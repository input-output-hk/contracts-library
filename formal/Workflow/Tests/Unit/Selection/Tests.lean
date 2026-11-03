import Workflow.App.Selection

namespace Workflow.Tests.Unit.Selection

open Workflow Workflow.App

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def accepted {α} (label : String) (result : Except String α) : IO α := do
  match result with
  | .ok value => return value
  | .error message => throw (IO.userError s!"FAIL: {label}: {message}")

private def rejected {α} (label : String) (result : Except String α) : IO Unit := do
  match result with
  | .ok _ => throw (IO.userError s!"FAIL: {label}: invalid selection was accepted")
  | .error message => check s!"{label}: explanation" (!message.isEmpty)

private def registry : Array CheckId := #[
  { propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-001" },
  { propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-002" },
  { propertyId := "UP-012", definitionVersion := 1, modelId := "TxM-007" },
  { propertyId := "UP-001", definitionVersion := 2, modelId := "TxM-009" }]

def run : IO Unit := do
  let bare ← accepted "bare request" (parseRequest [])
  check "bare request defaults" (bare.path == "plutus.json" &&
    bare.validators.isEmpty && bare.properties.isEmpty &&
    bare.checksFile.isNone && bare.timeoutMs == 300000 && bare.args.isEmpty)
  let flagArgs := ["--validator", "vault", "--check", "UP-001", "--timeout-ms", "5000"]
  let flags ← accepted "flags-only request" (parseRequest flagArgs)
  check "flags-only request controls" (flags.path == "plutus.json" &&
    flags.validators == #["vault"] && flags.properties == #["UP-001"] &&
    flags.timeoutMs == 5000 && flags.args == flagArgs.toArray)
  let flagFile ← accepted "flags-only selection file request"
    (parseRequest ["--checks-file", "checks.json"])
  check "flags-only selection file defaults" (flagFile.path == "plutus.json" &&
    flagFile.checksFile == some "checks.json" && flagFile.timeoutMs == 300000)
  let defaults ← accepted "default request" (parseRequest ["blueprint.json"])
  check "default request controls" (defaults.path == "blueprint.json" &&
    defaults.validators.isEmpty && defaults.properties.isEmpty &&
    defaults.checksFile.isNone && defaults.timeoutMs == 300000)
  let args := ["blueprint.json", "vault", "--validator", "vesting", "--check", "UP-012",
    "--check", "UP-001", "--timeout-ms", "120000"]
  let explicit ← accepted "explicit request" (parseRequest args)
  check "explicit path and original invocation retained"
    (explicit.path == "blueprint.json" && explicit.args == args.toArray)
  check "positional and repeated selection" (explicit.validators == #["vault", "vesting"] &&
    explicit.properties == #["UP-012", "UP-001"] && explicit.timeoutMs == 120000)
  let fileRequest ← accepted "selection file request"
    (parseRequest ["blueprint.json", "--checks-file", "checks.json"])
  check "selection file path" (fileRequest.checksFile == some "checks.json")
  for invalid in [[""], ["--unknown"], ["--validator"], ["--check", ""],
      ["--checks-file", "--check", "UP-001"], ["--timeout-ms", "0"],
      ["--timeout-ms", "abc"], ["--timeout-ms"],
      ["--check", "UP-001", "--checks-file", "checks.json"],
      ["blueprint.json", "one", "two"],
      ["blueprint.json", "--unknown"], ["blueprint.json", "--check"],
      ["blueprint.json", "--validator", "--check", "UP-001"],
      ["blueprint.json", "--checks-file", ""],
      ["blueprint.json", "--timeout-ms", "0"],
      ["blueprint.json", "--timeout-ms", "-1"],
      ["blueprint.json", "--timeout-ms", "1.5"],
      ["blueprint.json", "--timeout-ms", "5", "--timeout-ms", "6"],
      ["blueprint.json", "--checks-file", "one", "--checks-file", "two"],
      ["blueprint.json", "--check", "UP-001", "--checks-file", "checks.json"],
      ["blueprint.json", "--checks-file", "checks.json", "--check", "UP-001"]] do
    rejected "invalid arguments" (parseRequest invalid)

  let names := #["samples.vault", "vesting.linear", "other.vault", "../nested/name.special"]
  check "default validators preserve canonical order"
    ((← accepted "all validators" (selectValidators #[] names)) == names)
  check "validator filters preserve blueprint order and deduplicate aliases"
    ((← accepted "validator selection"
      (selectValidators #["special", "samples.vault", "special"] names)) ==
      #["samples.vault", "../nested/name.special"])
  check "validator selection preserves identity for safe output encoding"
    ((← accepted "path-like name" (selectValidators #["../nested/name.special"] names)) ==
      #["../nested/name.special"])
  rejected "ambiguous short validator" (selectValidators #["vault"] names)
  rejected "unknown validator" (selectValidators #["absent"] names)
  rejected "empty validator" (selectValidators #[""] names)

  check "no filter selects registered combinations"
    ((← accepted "all checks" (selectChecks defaults registry none)) == registry)
  let propertyRequest : Request := { path := "blueprint.json", properties := #["UP-001"] }
  check "property filter preserves all registered versions and models"
    ((← accepted "all models" (selectChecks propertyRequest registry none)) ==
      #[registry[0], registry[1], registry[3]])
  let reversed : Request := { propertyRequest with properties := #["UP-012", "UP-001", "UP-012"] }
  check "registry order and unique identities are preserved"
    ((← accepted "registry order" (selectChecks reversed (registry ++ #[registry[0]]) none)) == registry)
  check "switches enable true and disable false and omitted properties"
    ((← accepted "switch selection"
      (selectChecks fileRequest registry (some "{\"UP-012\": true, \"UP-001\": false}"))) ==
      #[registry[2]])
  check "omitted properties stay off"
    ((← accepted "omitted property"
      (selectChecks fileRequest registry (some "{\"UP-012\": true}"))) == #[registry[2]])
  for empty in ["{}", "{\"UP-001\": false, \"UP-012\": false}"] do
    check "empty enabled set is a valid no-op"
      ((← accepted "empty selection" (selectChecks fileRequest registry (some empty))).isEmpty)
  for invalid in ["{", "[]", "null", "{\"UP-001\": \"true\"}",
      "{\"UP-001\": 1}", "{\"UP-001\": null}", "{\"UP-999\": true}",
      "{\"UP-999\": false}"] do
    rejected "invalid selection file" (selectChecks fileRequest registry (some invalid))
  rejected "unknown explicit property"
    (selectChecks { defaults with properties := #["UP-999"] } registry none)
  rejected "missing selection contents" (selectChecks fileRequest registry none)
  rejected "unexpected selection contents" (selectChecks defaults registry (some "{}"))
  rejected "conflicting programmatic filters"
    (selectChecks { fileRequest with properties := #["UP-001"] } registry (some "{}"))
  IO.println "Selection checks passed."

end Workflow.Tests.Unit.Selection

def main : IO Unit := Workflow.Tests.Unit.Selection.run

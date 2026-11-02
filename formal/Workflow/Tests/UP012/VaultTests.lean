import Workflow.App.Run
import Workflow.Tests.Support
import Workflow.Tests.UP012.Profile
import Candidates.Catalogue
import Formal.TxModels.Definitions.TxM009

namespace Workflow.Tests.UP012.VaultTests

open Lean Workflow Workflow.Generator Workflow.Tests.Support

example (p : Formal.TxModels.TxM009.SpendLeaves) :
    (Formal.TxModels.TxM009.spend p).scriptContextTxInfo.txInfoSignatories = [p.signer] := rfl

example (p : Formal.TxModels.TxM009.SpendLeaves) (owner : PlutusCore.ByteString.ByteString) :
    (Formal.TxModels.TxM009.spend { p with owner }).scriptContextTxInfo.txInfoSignatories =
      (Formal.TxModels.TxM009.spend p).scriptContextTxInfo.txInfoSignatories := rfl

private def fixture := "Workflow/Tests/UP001/Inputs/plutus.json"
private def names := #["dropSigner_spend", "dropSigner_spend_applies"]

private def load : IO ConfiguredCheck :=
  do IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 "TxM-009")

private def source (plan : GenerationPlan) (suffix : String) : IO String := do
  let some result := plan.modules.find? (·.name.endsWith suffix)
    | throw (IO.userError s!"missing generated {suffix}")
  return result.source

def runUnit : IO Unit := do
  let configured ← load
  check "vault combination has exact property/version/model identity"
    (configured.context.propertyDefinition.id? == some "UP-012" &&
     configured.context.propertyDefinition.version? == some 1 &&
     configured.context.binding.txModel.id? == some "TxM-009")
  let mut plans : Array GenerationPlan := #[]
  for (selector, hash) in [
      ("vault.vault", "7ee33b926834bd7d983ca9d433cee0cc1918ed5bcb5f78ab795d7057"),
      ("vault_buggy.vault_buggy", "5d0f747d4eb70739ff667eed99b934de3a3e5054fae1e368902078e3")] do
    let input ← IO.ofExcept ((← Input.read fixture selector).mapError toString)
    let target := { input.target with handlers := input.target.handlers.map fun h =>
      { h with declaredHash := some "untrusted" } }
    let plan ← IO.ofExcept ((generateOne configured target "Generated.Vault").mapError toString)
    plans := plans.push plan
    check s!"{selector}: exactly two selected obligations and three modules"
      (plan.jobs.map (·.name) == names && plan.modules.size == 3)
    check s!"{selector}: both expectations remain Valid even for the buggy artifact"
      (plan.jobs.all fun job => job.expected == .valid && job.txModelId == some "TxM-009" &&
        job.binding == some configured.context.binding && !job.scope.isEmpty)
    let some main := plan.jobs[0]? | throw (IO.userError "missing vault property")
    let some support := plan.jobs[1]? | throw (IO.userError "missing vault applicability")
    check "spend applicability qualifies only its linked property"
      (main.role == .property && main.applicability == some { moduleName := support.moduleName, name := support.name } &&
       support.role == .applicability && support.applicability.isNone)
    let types ← source plan ".Types"
    check s!"{selector}: exact compiled program and independently pinned hash"
      ((types.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr target.compiledCode}").length == 2 &&
       (types.splitOn s!"def scriptHashHex : String := {reprStr hash}").length == 2)
    let tx ← source plan ".Tx"
    let checks ← source plan ".Checks"
    check "vault uses the native symbolic model and shared unchanged formula"
      ((tx.splitOn "abbrev spend := Formal.TxModels.TxM009.spend").length == 2 &&
       (checks.splitOn "Formal.Properties.Universal.UP012.statement validScriptContext (accepts ledgerFuel) (rejects ledgerFuel) spend").length == 2 &&
       (checks.splitOn "owner").length == 1 && (tx.splitOn "owner").length == 1 &&
       (checks.splitOn "import Formal.Properties.Universal.UP012.Definition").length == 2 &&
       plan.jobs.all (fun job => (job.scope.splitOn "1,000,000-step bound").length == 2))
    let legacy ← IO.ofExcept ((generate Profile.provider target "Generated.Vault").mapError toString)
    check "legacy provider selects the same two vault jobs" (legacy.jobs.map (·.name) == names)
    let empty := { target with parameters := some #[] }
    check "explicit empty parameters are supported"
      ((generateOne configured empty "Generated.Vault").toOption.isSome)
    for model in ["TxM-007", "TxM-008"] do
      let vestingCheck ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 model)
      match generateOne vestingCheck target "Generated.UnsupportedVault" with
      | .error error => check s!"{model} rejects a vault target" (error.kind == .unsupported)
      | .ok _ => throw (IO.userError s!"{model} accepted a vault target")
    let extraPurpose : HandlerDescription :=
      { name := "fixture.target.mint", purpose := some .mint,
        datum := none, redeemer := none, declaredHash := none }
    let parameter : ArgumentDescription :=
      { schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
    check "input-compatible new compiled code requires no artifact registration"
      ((generateOne configured { target with compiledCode := "480100002221200101" }
        "Generated.NewProgram").toOption.isSome)
    check "an unrelated declared purpose does not prevent spending preparation"
      ((generateOne configured { target with handlers := target.handlers.push extraPurpose }
        "Generated.AdditionalPurpose").toOption.isSome)
    match generateOne configured { target with compiledCode := target.compiledCode ++ "00" }
        "Generated.InvalidProgram" with
    | .error error =>
      check "malformed prepared code is an error rather than an unsupported schema"
        (error.kind == .invalidPlan)
    | .ok _ => throw (IO.userError "trailing compiled bytes were accepted")
    for unsupported in [
        { target with plutusVersion := "v2" },
        { target with parameters := some #[parameter] },
        { target with handlers := #[] }] do
      match generateOne configured unsupported "Generated.Vault" with
      | .error error => check "unsupported vault mutation is explicit" (error.kind == .unsupported)
      | .ok _ => throw (IO.userError "unsupported vault mutation accepted")
  let vesting ← IO.ofExcept ((← Input.read "Workflow/Tests/UP012/Inputs/plutus.json"
    "linear_vesting.linear_vesting").mapError toString)
  match generateOne configured vesting.target "Generated.UnsupportedVesting" with
  | .error error => check "TxM-009 rejects a vesting target" (error.kind == .unsupported)
  | .ok _ => throw (IO.userError "TxM-009 accepted a vesting target")
  let some normalPlan := plans[0]? | throw (IO.userError "missing normal plan")
  let some buggyPlan := plans[1]? | throw (IO.userError "missing buggy plan")
  for suffix in [".Tx", ".Checks"] do
    check s!"both artifacts share identical {suffix} source"
      ((← source normalPlan suffix) == (← source buggyPlan suffix))
  check "only Types differ between the two artifacts"
    ((← source normalPlan ".Types") != (← source buggyPlan ".Types"))
  IO.println "UP012 vault generator checks passed."

private def evidenceDirectory (result : Assessor.CheckResult) : IO System.FilePath := do
  let some input := result.evidence.find? (·.fileName == some "input.json")
    | throw (IO.userError "missing retained vault input")
  let some directory := input.parent
    | throw (IO.userError "missing vault evidence directory")
  return directory

def run : IO Unit := do
  runUnit
  startCase "UP012: normal and buggy vault signer removal"
    "normal PASS; buggy FAIL with Falsified property; both applicability obligations Valid"
    "App.Run.runWith [UP-012 v1 / TxM-009], both vault validators" 300000
  let configured ← load
  let leanPath := (← IO.getEnv "LEAN_PATH").getD ""
  check "vault solver tests receive a prepared Lean search path" (!leanPath.trim.isEmpty)
  let id : CheckId := { propertyId := "UP-012", definitionVersion := 1, modelId := "TxM-009" }
  let run ← App.Run.runWith #[id]
    (fun selected => Candidates.Catalogue.loadCheck selected.propertyId selected.definitionVersion selected.modelId)
    { path := fixture, validators := #["vault.vault", "vault_buggy.vault_buggy"], timeoutMs := 300000 }
    { executorOptions := { leanPath }, outputRoot := "output" }
  check "vault run completes with both selected validators" (run.finished && run.exitCode == 0 && run.validators.size == 2)
  check "saved vault run index matches the actual workflow"
    ((← IO.ofExcept (Json.parse (← IO.FS.readFile (run.directory / "run.json")))) == run.toJson)
  for file in ["README.md", "sources/index.json"] do
    check s!"vault run retains {file}" (← (run.directory / file).pathExists)
  for validator in run.validators do
    check "vault run retains exactly the requested combination"
      (validator.checks.size == 1 && validator.checks[0]!.id == id)
    let some result := validator.checks[0]!.result
      | throw (IO.userError "vault workflow has no assessed result")
    let directory ← evidenceDirectory result
    IO.println s!"Vault check result: {directory / "check-result.json"}"
    showCompilerLogs directory
    let buggy := validator.name == "vault_buggy.vault_buggy"
    check "vault observed status matches its independent scenario expectation"
      (result.status == (if buggy then .fail else .pass) && result.check == configured.context)
    check "vault obligations preserve exact metadata, Valid expectations, and complete evidence"
      (result.obligations.map (·.job.name) == names && result.obligations.all fun row =>
        row.job.binding == some configured.context.binding && row.job.txModelId == some "TxM-009" &&
        row.job.expected == .valid && row.evidenceComplete)
    let some main := result.obligations[0]? | throw (IO.userError "missing property observation")
    let some support := result.obligations[1]? | throw (IO.userError "missing applicability observation")
    check "vault applicability is directly Valid for both artifacts"
      (support.observed == some .valid && support.status == .pass)
    check "buggy vault has direct Falsified evidence; normal vault is Valid"
      (main.observed == some (if buggy then .falsified else .valid))
    check "saved vault check result matches returned metadata and observations"
      ((← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "check-result.json")))) == result.toJson)
    for reference in result.evidence do
      check "vault evidence references retained files" (← reference.pathExists)
  IO.println "UP012 vault whole-workflow checks passed (the buggy property failure is intentional)."

end Workflow.Tests.UP012.VaultTests

import Formal.Properties.Universal.UP004.Run
import Formal.Properties.Universal.UP004.Tests.Parity
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.Support

namespace Formal.Properties.Universal.UP004.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM007", runnable := TxModels.TxM007.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM008", runnable := TxModels.TxM008.runnable }]

private def property (run : PropertyRun := UP004.run) : Property := {
  run
  runModule := "Formal.Properties.Universal.UP004.Run"
  definitionModule := "Formal.Properties.Universal.UP004.Definition"
  metadataPath := "Formal/Properties/Universal/UP004/metadata.json" }

private def contains (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def expectError (label : String) (kind : Generator.ErrorKind)
    (result : Except Generator.Error GenerationPlan) : IO Unit := do
  match result with
  | .error error => check label (error.kind == kind)
  | .ok _ => throw (IO.userError s!"FAIL: {label}: generated an unexpected plan")

def unit : IO Unit := do
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] models)
  let ids : Array CheckId := #[
    { propertyId := "UP-004", definitionVersion := 1, modelId := "TxM-007" },
    { propertyId := "UP-004", definitionVersion := 1, modelId := "TxM-008" }]
  check "UP-004 registers exactly Claim and Cancel" (catalogue.checks == ids)
  check "each existential uses the original bound and no applicability obligation"
    (UP004.run.fuel == 1000000 && UP004.run.applicability.isNone)
  let metadata ← IO.ofExcept (← PropertyDefinition.readRecord (property).metadataPath)
  check "metadata identifies the native UP-004 definition"
    (metadata.id? == some "UP-004" && metadata.version? == some 1 &&
     metadata.primary? == some "Formal.Properties.Universal.UP004.statement")
  let metadataScope ← IO.ofExcept do
    let scope ← metadata.toJson.getObjVal? "scope"
    scope.getObjVal? "limitations"
  for fragment in #["reference artifact", "p.script", "1 ADA", "witness", "ledger reachability",
      "CEK", "Fuel exhaustion", "timeout", "blasterProven", "#25", "#96"] do
    check s!"metadata retains the {fragment} limitation" (contains metadataScope.compress fragment)
  let input ← IO.ofExcept ((← Input.read "Workflow/Tests/UP012/Inputs/plutus.json"
    "linear_vesting.linear_vesting").mapError toString)
  check "the supplied fixture is the reference artifact"
    (input.target.compiledCode == TxModels.Artifacts.LinearVesting.referenceCompiledCode)
  let legacyTypes ← IO.FS.readFile "Formal/Vesting/Linear/Blueprint/Types.lean"
  check "the frozen evaluator embeds the same reference bytes"
    (contains legacyTypes s!"singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}")
  let alternate ← IO.ofExcept ((← Input.read
    "Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json"
    "linear_vesting.linear_vesting").mapError toString)
  check "the skip control uses the other artifact admitted by the shared models"
    (alternate.target.compiledCode == TxModels.Artifacts.LinearVesting.aiken1121CompiledCode &&
     alternate.target.compiledCode != input.target.compiledCode)
  let vault ← IO.ofExcept ((← Input.read "Workflow/Tests/UP001/Inputs/plutus.json"
    "vault.vault").mapError toString)
  let parameter : ArgumentDescription := {
    schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
  for (id, action) in ids.zip #["claim", "cancel"] do
    let configured ← IO.ofExcept (catalogue.loadCheck id)
    let some selected := UP004.run.models.find? (·.id == id.modelId)
      | throw (IO.userError "missing selected model")
    let binding := configured.context.binding
    check s!"{id.modelId}: property and model snapshots retain the selected identity"
      (configured.context.propertyDefinition == metadata &&
       binding.combinedCheck.propertyId? == some "UP-004" &&
       binding.combinedCheck.definitionVersion? == some 1 &&
       binding.combinedCheck.txModelId? == some id.modelId &&
       binding.txModel.id? == some id.modelId && binding.txModel.plutusVersion? == some "v3")
    check s!"{id.modelId}: every pairing limitation reaches the binding"
      (!selected.limitations.isEmpty &&
       (binding.combinedCheck.toJson.getObjVal? "limitations").toOption ==
         some (toJson selected.limitations))
    let plan ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.UP004").mapError toString)
    let [job] := plan.jobs.toList | throw (IO.userError "expected one existential job")
    check s!"{id.modelId}: one expected-Valid existential retains its binding and scope"
      (job.name == s!"someRejected_{action}" && job.propertyId == "UP-004" &&
       job.expected == .valid && job.role == .property && job.applicability.isNone &&
       job.txModelId == some id.modelId && job.binding == some binding &&
       contains job.scope "1,000,000 CEK steps" &&
       contains job.scope "fuel exhaustion does not count" &&
       plan.propertyDefinition == some metadata)
    check s!"{id.modelId}: the generated formula preserves validity, explicit rejection, and fuel"
      (job.statement == s!"Formal.Properties.Universal.UP004.statement validScriptContext (rejects 1000000) {action}")
    let some types := plan.modules.find? (·.name == "Generated.UP004.Types")
      | throw (IO.userError "missing evaluator module")
    check s!"{id.modelId}: the prepared evaluator matches the kernel parity formula"
      (contains types.source "def args (ctx : ScriptContext) : List Term := [toTerm ctx]" &&
       contains types.source s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}" &&
       contains types.source "def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  Formal.Support.rejectedWithin program (args ctx) fuel")
    check s!"{id.modelId}: the prepared hash is computed from the reference bytes"
      (contains types.source s!"def scriptHashHex : String := {reprStr Formal.Vesting.Linear.Blueprint.scriptHashHex}")
    let some model := models.find? (·.runnable.metadata.id == id.modelId)
      | throw (IO.userError "missing native model")
    check s!"{id.modelId}: generation uses the unchanged native context builder"
      (plan.modules.any fun source => source.name == "Generated.UP004.Tx" &&
        contains source.source s!"abbrev {action} := {model.runnable.context}")
    let skipped ← IO.ofExcept ((Generator.generateOne configured alternate.target "Generated.Skipped").mapError toString)
    check s!"{id.modelId}: the other admitted artifact produces no executable obligations"
      (skipped.status == .noObligations && skipped.jobs.isEmpty && skipped.modules.isEmpty &&
       skipped.propertyDefinition == some metadata &&
       skipped.notes.any (contains · "reference linear-vesting compiled artifact"))
    for unsupported in #[vault.target,
        { input.target with compiledCode := input.target.compiledCode ++ "00" },
        { input.target with plutusVersion := "v2" },
        { input.target with parameters := some #[parameter] },
        { input.target with handlers := #[] }] do
      expectError s!"{id.modelId}: incompatible targets stop before execution" .unsupported
        (Generator.generateOne configured unsupported "Generated.Unsupported")
    for (propertyId, version, modelId) in [
        ("UP-012", (1 : Int), id.modelId), ("UP-004", 2, id.modelId),
        ("UP-004", 1, "TxM-999")] do
      let malformed ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
        ("property", Json.mkObj [("id", .str propertyId), ("definition_version", toJson version)]),
        ("tx_model", .str modelId)]))
      let bad : Generator.ConfiguredCheck := { configured with
        context := { configured.context with
          binding := { binding with combinedCheck := malformed } } }
      expectError s!"{id.modelId}: inconsistent binding identity stops before execution" .invalidPlan
        (Generator.generateOne bad input.target "Generated.Malformed")
  check "an unregistered model cannot be selected"
    ((catalogue.loadCheck { propertyId := "UP-004", definitionVersion := 1, modelId := "TxM-009" }).toOption.isNone)
  for invalid in [
      { UP004.run with models := #[{ id := "TxM-999" }] },
      { UP004.run with models := #[{ id := "TxM-007" }, { id := "TxM-007" }] },
      { UP004.run with statement := { UP004.run.statement with definition := ``Nat.add } }] do
    check "unknown models, duplicate selections, and mismatched definitions are rejected"
      (← Catalogue.load #[property invalid] models).toOption.isNone
  let some firstModel := models[0]? | throw (IO.userError "missing model fixture")
  check "duplicate model exports are rejected"
    (← Catalogue.load #[property] (models.push firstModel)).toOption.isNone
  IO.println "Declarative UP-004 unit checks passed: registration, parity, bindings, scope, and admission controls."

end Formal.Properties.Universal.UP004.Tests

def main : IO Unit := Formal.Properties.Universal.UP004.Tests.unit

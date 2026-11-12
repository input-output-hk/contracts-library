import Formal.Properties.Universal.UP013.Run
import Formal.Properties.Universal.UP013.Tests.Parity
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.Support

namespace Formal.Properties.Universal.UP013.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM007", runnable := TxModels.TxM007.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM008", runnable := TxModels.TxM008.runnable }]

private def property (run : PropertyRun := UP013.run) : Property := {
  run
  runModule := "Formal.Properties.Universal.UP013.Run"
  definitionModule := "Formal.Properties.Universal.UP013.Definition"
  metadataPath := "Formal/Properties/Universal/UP013/metadata.json" }

private def contains (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def expectError (label : String) (kind : Generator.ErrorKind)
    (result : Except Generator.Error GenerationPlan) : IO Unit := do
  match result with
  | .error error => check label (error.kind == kind)
  | .ok _ => throw (IO.userError s!"FAIL: {label}: generated an unexpected plan")

def unit : IO Unit := do
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] models)
  let ids : Array CheckId := #[
    { propertyId := "UP-013", definitionVersion := 1, modelId := "TxM-007" },
    { propertyId := "UP-013", definitionVersion := 1, modelId := "TxM-008" }]
  check "UP-013 registers exactly Claim and Cancel" (catalogue.checks == ids)
  check "the rejection check keeps the original bound, names, and applicability"
    (UP013.run.fuel == 1000000 && UP013.run.theoremPrefix == "unboundedRange" &&
     UP013.run.applicability.isSome)
  let metadata ← IO.ofExcept (← PropertyDefinition.readRecord (property).metadataPath)
  check "metadata identifies the native UP-013 definition"
    (metadata.id? == some "UP-013" && metadata.version? == some 1 &&
     metadata.primary? == some "Formal.Properties.Universal.UP013.statement")
  let metadataScope ← IO.ofExcept do
    let scope ← metadata.toJson.getObjVal? "scope"
    scope.getObjVal? "limitations"
  for fragment in #["reference artifact", "rangeAlways", "three premises", "No extra premise",
      "missing lower bound", "p.script", "1 ADA", "witness", "ledger reachability", "CEK",
      "fuel exhaustion", "timeout", "blasterProven", "#34", "#96"] do
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
    let some selected := UP013.run.models.find? (·.id == id.modelId)
      | throw (IO.userError "missing selected model")
    let some model := models.find? (·.runnable.metadata.id == id.modelId)
      | throw (IO.userError "missing native model")
    let nativeMetadata ← IO.ofExcept (TransactionModel.parse model.runnable.metadata.toJson)
    let binding := configured.context.binding
    check s!"{id.modelId}: property and model snapshots retain the selected identity"
      (configured.context.propertyDefinition == metadata && binding.txModel == nativeMetadata &&
       binding.combinedCheck.propertyId? == some "UP-013" &&
       binding.combinedCheck.definitionVersion? == some 1 &&
       binding.combinedCheck.txModelId? == some id.modelId)
    check s!"{id.modelId}: every pairing limitation reaches the binding"
      (!selected.limitations.isEmpty &&
       (binding.combinedCheck.toJson.getObjVal? "limitations").toOption ==
         some (toJson selected.limitations))
    let plan ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.UP013").mapError toString)
    let [mainJob, support] := plan.jobs.toList
      | throw (IO.userError "expected one rejection job and one applicability job")
    check s!"{id.modelId}: both expected-Valid obligations retain the binding and scope"
      (plan.propertyDefinition == some metadata && plan.jobs.all fun job =>
        job.expected == .valid && job.propertyId == "UP-013" &&
        job.txModelId == some id.modelId && job.binding == some binding &&
        contains job.scope "1,000,000 CEK steps" &&
        contains job.scope "Fuel exhaustion does not establish rejection" &&
        contains job.scope "separate applicability obligation")
    check s!"{id.modelId}: the main obligation links only its own applicability job"
      (mainJob.name == s!"unboundedRange_{action}" && mainJob.role == .property &&
       support.name == s!"unboundedRange_{action}_applies" && support.role == .applicability &&
       support.applicability.isNone &&
       mainJob.applicability == some { moduleName := support.moduleName, name := support.name })
    check s!"{id.modelId}: formulas preserve the three premises, evaluators, and bound"
      (mainJob.statement == s!"Formal.Properties.Universal.UP013.statement validScriptContext (accepts 1000000) (rejects 1000000) {action}" &&
       support.statement == s!"Formal.Properties.Universal.UP013.applicability validScriptContext (accepts 1000000) {action}")
    let some types := plan.modules.find? (·.name == "Generated.UP013.Types")
      | throw (IO.userError "missing evaluator module")
    check s!"{id.modelId}: the prepared evaluators match the kernel parity formulas"
      (contains types.source "def args (ctx : ScriptContext) : List Term := [toTerm ctx]" &&
       contains types.source s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}" &&
       contains types.source "def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)" &&
       contains types.source "def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  Formal.Support.rejectedWithin program (args ctx) fuel")
    check s!"{id.modelId}: the prepared hash is computed from the reference bytes"
      (contains types.source s!"def scriptHashHex : String := {reprStr Formal.Vesting.Linear.Blueprint.scriptHashHex}")
    check s!"{id.modelId}: generation uses the unchanged native context builder"
      (plan.modules.any fun source => source.name == "Generated.UP013.Tx" &&
        contains source.source s!"abbrev {action} := {model.runnable.context}")
    check s!"{id.modelId}: generated proofs unfold only the native property definitions"
      ((plan.modules.any fun source => source.name == "Generated.UP013.Checks" &&
        contains source.source "unfold Formal.Properties.Universal.UP013.statement" &&
        contains source.source "unfold Formal.Properties.Universal.UP013.applicability") &&
       plan.modules.all fun source => !contains source.source "Blueprint.UnboundedRange")
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
        ("UP-012", (1 : Int), id.modelId), ("UP-013", 2, id.modelId),
        ("UP-013", 1, "TxM-999")] do
      let malformed ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
        ("property", Json.mkObj [("id", .str propertyId), ("definition_version", toJson version)]),
        ("tx_model", .str modelId)]))
      let bad : Generator.ConfiguredCheck := { configured with
        context := { configured.context with
          binding := { binding with combinedCheck := malformed } } }
      expectError s!"{id.modelId}: inconsistent binding identity stops before execution" .invalidPlan
        (Generator.generateOne bad input.target "Generated.Malformed")
    let some otherModel := models.find? (·.runnable.metadata.id != id.modelId)
      | throw (IO.userError "missing mismatched model fixture")
    let otherMetadata ← IO.ofExcept (TransactionModel.parse otherModel.runnable.metadata.toJson)
    let mismatched : Generator.ConfiguredCheck := { configured with
      context := { configured.context with binding := { binding with txModel := otherMetadata } } }
    expectError s!"{id.modelId}: another model's metadata cannot replace its binding" .invalidPlan
      (Generator.generateOne mismatched input.target "Generated.Mismatched")
  check "an unregistered model cannot be selected"
    ((catalogue.loadCheck { propertyId := "UP-013", definitionVersion := 1, modelId := "TxM-009" }).toOption.isNone)
  for invalid in [
      { UP013.run with models := #[{ id := "TxM-999" }] },
      { UP013.run with models := #[{ id := "TxM-007" }, { id := "TxM-007" }] },
      { UP013.run with statement := { UP013.run.statement with definition := ``Nat.add } }] do
    check "unknown models, duplicate selections, and mismatched definitions are rejected"
      (← Catalogue.load #[property invalid] models).toOption.isNone
  let some firstModel := models[0]? | throw (IO.userError "missing model fixture")
  check "duplicate model exports are rejected"
    (← Catalogue.load #[property] (models.push firstModel)).toOption.isNone
  IO.println "Declarative UP-013 unit checks passed: registration, parity, applicability links, bindings, and admission controls."

end Formal.Properties.Universal.UP013.Tests

def main : IO Unit := Formal.Properties.Universal.UP013.Tests.unit

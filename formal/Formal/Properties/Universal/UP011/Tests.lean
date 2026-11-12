import Formal.Properties.Universal.UP011.Run
import Formal.Properties.Universal.UP011.Tests.Parity
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.Support

namespace Formal.Properties.Universal.UP011.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM007", runnable := TxModels.TxM007.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM008", runnable := TxModels.TxM008.runnable }]

private def property (run : PropertyRun := UP011.run) : Property := {
  run
  runModule := "Formal.Properties.Universal.UP011.Run"
  definitionModule := "Formal.Properties.Universal.UP011.Definition"
  metadataPath := "Formal/Properties/Universal/UP011/metadata.json" }

private def contains (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def expectError (label : String) (kind : Generator.ErrorKind)
    (result : Except Generator.Error GenerationPlan) : IO Unit := do
  match result with
  | .error error => check label (error.kind == kind)
  | .ok _ => throw (IO.userError s!"FAIL: {label}: generated an unexpected plan")

def unit : IO Unit := do
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] models)
  let id : CheckId := { propertyId := "UP-011", definitionVersion := 1, modelId := "TxM-007" }
  check "UP-011 registers exactly Claim" (catalogue.checks == #[id])
  check "the rejection check keeps the original bound, names, and applicability"
    (UP011.run.fuel == 1000000 && UP011.run.theoremPrefix == "continuationElsewhere" &&
     UP011.run.applicability.isSome)
  let metadata ← IO.ofExcept (← PropertyDefinition.readRecord (property).metadataPath)
  check "metadata identifies the native UP-011 definition"
    (metadata.id? == some "UP-011" && metadata.version? == some 1 &&
     metadata.primary? == some "Formal.Properties.Universal.UP011.statement")
  let metadataScope ← IO.ofExcept do
    let scope ← metadata.toJson.getObjVal? "scope"
    scope.getObjVal? "limitations"
  for fragment in #["reference artifact", "five", "staking", "datum", "p.script", "1 ADA",
      "witness", "ledger reachability", "CEK", "fuel exhaustion", "timeout", "blasterProven", "Cancel"] do
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
  check "the skip control uses the other artifact admitted by the shared model"
    (alternate.target.compiledCode == TxModels.Artifacts.LinearVesting.aiken1121CompiledCode &&
     alternate.target.compiledCode != input.target.compiledCode)
  let configured ← IO.ofExcept (catalogue.loadCheck id)
  let some selected := UP011.run.models.find? (·.id == id.modelId)
    | throw (IO.userError "missing selected model")
  let some model := models.find? (·.runnable.metadata.id == id.modelId)
    | throw (IO.userError "missing native model")
  let nativeMetadata ← IO.ofExcept (TransactionModel.parse model.runnable.metadata.toJson)
  let binding := configured.context.binding
  check "property and model snapshots retain the selected identity"
    (configured.context.propertyDefinition == metadata && binding.txModel == nativeMetadata &&
     binding.combinedCheck.propertyId? == some "UP-011" &&
     binding.combinedCheck.definitionVersion? == some 1 &&
     binding.combinedCheck.txModelId? == some "TxM-007")
  check "every pairing limitation reaches the binding"
    (!selected.limitations.isEmpty &&
     (binding.combinedCheck.toJson.getObjVal? "limitations").toOption ==
       some (toJson selected.limitations))
  let plan ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.UP011").mapError toString)
  let [mainJob, support] := plan.jobs.toList
    | throw (IO.userError "expected one rejection job and one applicability job")
  check "both expected-Valid obligations retain the binding and scope"
    (plan.propertyDefinition == some metadata && plan.jobs.all fun job =>
      job.expected == .valid && job.propertyId == "UP-011" &&
      job.txModelId == some "TxM-007" && job.binding == some binding &&
      contains job.scope "1,000,000 CEK steps" &&
      contains job.scope "Fuel exhaustion does not establish rejection" &&
      contains job.scope "five guards" && contains job.scope "check applicability separately")
  check "the main obligation links only its own applicability job"
    (mainJob.name == "continuationElsewhere_claim" && mainJob.role == .property &&
     support.name == "continuationElsewhere_claim_applies" && support.role == .applicability &&
     support.applicability.isNone &&
     mainJob.applicability == some { moduleName := support.moduleName, name := support.name })
  check "both formulas retain acceptance, explicit rejection, and the original bound"
    (mainJob.statement == "Formal.Properties.Universal.UP011.statement validScriptContext (accepts 1000000) (rejects 1000000) claim" &&
     support.statement == "Formal.Properties.Universal.UP011.applicability validScriptContext (accepts 1000000) (rejects 1000000) claim")
  let some types := plan.modules.find? (·.name == "Generated.UP011.Types")
    | throw (IO.userError "missing evaluator module")
  check "the prepared evaluators match the kernel parity formulas"
    (contains types.source "def args (ctx : ScriptContext) : List Term := [toTerm ctx]" &&
     contains types.source s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}" &&
     contains types.source "def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)" &&
     contains types.source "def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  Formal.Support.rejectedWithin program (args ctx) fuel")
  check "the prepared hash is computed from the reference bytes"
    (contains types.source s!"def scriptHashHex : String := {reprStr Formal.Vesting.Linear.Blueprint.scriptHashHex}")
  check "generation uses the unchanged native Claim context builder"
    (plan.modules.any fun source => source.name == "Generated.UP011.Tx" &&
      contains source.source s!"abbrev claim := {model.runnable.context}")
  let some checks := plan.modules.find? (·.name == "Generated.UP011.Checks")
    | throw (IO.userError "missing checks module")
  for (job, definition) in [(mainJob, "statement"), (support, "applicability")] do
    check s!"{job.name}: generated source matches the registered job"
      (contains checks.source s!"theorem {job.name} :\n    {job.statement} := by\n  unfold Formal.Properties.Universal.UP011.{definition}\n  blaster")
  check "generated proofs use native definitions without standalone or Cancel imports"
    (contains checks.source "import Formal.Properties.Universal.UP011.Definition" &&
     contains checks.source "import Formal.Properties.Universal.UP011.Run" &&
     plan.modules.all fun source =>
       !contains source.source "Blueprint.ContinuationElsewhere" &&
       !contains source.source "Tests.Standalone" &&
       !contains source.source "continuationElsewhere_cancel" &&
       !contains source.source "TxM008")
  let skipped ← IO.ofExcept ((Generator.generateOne configured alternate.target "Generated.Skipped").mapError toString)
  check "the other admitted artifact produces no executable obligations"
    (skipped.status == .noObligations && skipped.jobs.isEmpty && skipped.modules.isEmpty &&
     skipped.propertyDefinition == some metadata &&
     skipped.notes.any (contains · "reference linear-vesting compiled artifact"))
  let vault ← IO.ofExcept ((← Input.read "Workflow/Tests/UP001/Inputs/plutus.json"
    "vault.vault").mapError toString)
  let parameter : ArgumentDescription := {
    schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
  for unsupported in #[vault.target,
      { input.target with compiledCode := input.target.compiledCode ++ "00" },
      { input.target with plutusVersion := "v2" },
      { input.target with parameters := some #[parameter] },
      { input.target with handlers := #[] }] do
    expectError "incompatible targets stop before execution" .unsupported
      (Generator.generateOne configured unsupported "Generated.Unsupported")
  for (propertyId, version, modelId) in [
      ("UP-012", (1 : Int), "TxM-007"), ("UP-011", 2, "TxM-007"),
      ("UP-011", 1, "TxM-008"), ("UP-011", 1, "TxM-999")] do
    let malformed ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
      ("property", Json.mkObj [("id", .str propertyId), ("definition_version", toJson version)]),
      ("tx_model", .str modelId)]))
    let bad : Generator.ConfiguredCheck := { configured with
      context := { configured.context with
        binding := { binding with combinedCheck := malformed } } }
    expectError "inconsistent binding identity stops before execution" .invalidPlan
      (Generator.generateOne bad input.target "Generated.Malformed")
  let some cancelModel := models.find? (·.runnable.metadata.id == "TxM-008")
    | throw (IO.userError "missing Cancel model fixture")
  let cancelMetadata ← IO.ofExcept (TransactionModel.parse cancelModel.runnable.metadata.toJson)
  let mismatched : Generator.ConfiguredCheck := { configured with
    context := { configured.context with binding := { binding with txModel := cancelMetadata } } }
  expectError "Cancel metadata cannot replace the Claim binding" .invalidPlan
    (Generator.generateOne mismatched input.target "Generated.Mismatched")
  for modelId in #["TxM-008", "TxM-009"] do
    check s!"{modelId} cannot be selected as a native UP-011 pair"
      ((catalogue.loadCheck { id with modelId }).toOption.isNone)
  expectError "Cancel cannot bypass selection through direct generation" .unsupported
    (Workflow.Declarative.generate "UP-011" property cancelModel input.target "Generated.Cancel")
  for invalid in [
      { UP011.run with models := #[{ id := "TxM-999" }] },
      { UP011.run with models := #[{ id := "TxM-007" }, { id := "TxM-007" }] },
      { UP011.run with statement := { UP011.run.statement with definition := ``Nat.add } }] do
    check "unknown models, duplicate selections, and mismatched definitions are rejected"
      (← Catalogue.load #[property invalid] models).toOption.isNone
  check "duplicate model exports are rejected"
    (← Catalogue.load #[property] (models.push model)).toOption.isNone
  IO.println "Declarative UP-011 unit checks passed: Claim registration, parity, applicability links, bindings, and admission controls."

end Formal.Properties.Universal.UP011.Tests

def main : IO Unit := Formal.Properties.Universal.UP011.Tests.unit

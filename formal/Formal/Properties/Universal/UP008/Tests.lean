import Formal.Properties.Universal.UP008.Run
import Formal.Properties.Universal.UP008.Tests.Parity
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.Support

namespace Formal.Properties.Universal.UP008.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (TxInInfo TxOut TxOutRef)
open Formal.Support.Continuations (keyAddr)

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM007", runnable := TxModels.TxM007.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM008", runnable := TxModels.TxM008.runnable }]

private def property (run : PropertyRun := UP008.run) : Property := {
  run
  runModule := "Formal.Properties.Universal.UP008.Run"
  definitionModule := "Formal.Properties.Universal.UP008.Definition"
  metadataPath := "Formal/Properties/Universal/UP008/metadata.json" }

private def contains (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def expectError (label : String) (kind : Generator.ErrorKind)
    (result : Except Generator.Error GenerationPlan) : IO Unit := do
  match result with
  | .error error => check label (error.kind == kind)
  | .ok _ => throw (IO.userError s!"FAIL: {label}: generated an unexpected plan")

-- These checks cover mutation structure without asserting validity or program acceptance.
private def mutationShape : IO Unit := do
  let leaves : TxModels.TxM007.ClaimLeaves := {
    beneficiary := "01", locker := "02", name := "00", total := 10,
    start := 0, finish := 100, recovery := 200, script := "03",
    prevTx := "00", txId := "01", scriptAda := 10, feeInputAda := 10,
    keptAda := 10, kept := 5, fee := 1, now := 50, signer := "01" }
  let baseline := TxModels.TxM007.claim leaves
  let ref : TxOutRef := ⟨"04", 2⟩
  let junk : Data × Data := (.B "zzzzjunk", .Map [(.B "zzzzjunk", .I 1)])
  let [continuation, payout] := baseline.scriptContextTxInfo.txInfoOutputs
    | throw (IO.userError "expected the fixed two-output Claim model")
  check "junk policy, asset name, and unrelated key retain their original bytes"
    (UP008.lastPolicy == "zzzzjunk" && UP008.unrelatedKey == "756e72656c61746564")
  for lovelace in [(-1 : Int), 0, 7000000] do
    let changed := addJunkFrom baseline ref lovelace
    let funding : TxInInfo := ⟨ref, ⟨keyAddr unrelatedKey,
      [(.B "", .Map [(.B "", .I lovelace)]), junk], .NoOutputDatum, none⟩⟩
    let returned : TxOut := ⟨keyAddr unrelatedKey,
      [(.B "", .Map [(.B "", .I lovelace)])], .NoOutputDatum, none⟩
    check "the mutation appends one funding input without changing existing inputs"
      (changed.scriptContextTxInfo.txInfoInputs ==
        baseline.scriptContextTxInfo.txInfoInputs ++ [funding])
    check "one fixed junk unit reaches the first continuation and lovelace reaches its own output"
      (changed.scriptContextTxInfo.txInfoOutputs ==
        [{ continuation with txOutValue := List.append continuation.txOutValue [junk] }, payout, returned])
    check "the fixed Claim mutation has three inputs and three outputs"
      (changed.scriptContextTxInfo.txInfoInputs.length == 3 &&
       changed.scriptContextTxInfo.txInfoOutputs.length == 3)
    check "the mutation preserves the redeemer, script info, and remaining transaction fields"
      (changed.scriptContextRedeemer == baseline.scriptContextRedeemer &&
       changed.scriptContextScriptInfo == baseline.scriptContextScriptInfo &&
       { changed.scriptContextTxInfo with
           txInfoInputs := baseline.scriptContextTxInfo.txInfoInputs
           txInfoOutputs := baseline.scriptContextTxInfo.txInfoOutputs } ==
         baseline.scriptContextTxInfo)

def unit : IO Unit := do
  mutationShape
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] models)
  let id : CheckId := { propertyId := "UP-008", definitionVersion := 1, modelId := "TxM-007" }
  check "UP-008 registers exactly Claim" (catalogue.checks == #[id])
  check "the rejection check keeps the original bound, names, and applicability"
    (UP008.run.fuel == 1000000 && UP008.run.theoremPrefix == "junkToken" &&
     UP008.run.applicability.isSome)
  let metadata ← IO.ofExcept (← PropertyDefinition.readRecord (property).metadataPath)
  check "metadata identifies the native UP-008 definition"
    (metadata.id? == some "UP-008" && metadata.version? == some 1 &&
     metadata.primary? == some "Formal.Properties.Universal.UP008.statement")
  let metadataScope ← IO.ofExcept do
    let scope ← metadata.toJson.getObjVal? "scope"
    scope.getObjVal? "limitations"
  for fragment in #["reference artifact", "four", "zzzzjunk", "lovelace", "p.script",
      "witness", "ledger reachability", "CEK", "fuel exhaustion", "timeout", "blasterProven", "Cancel"] do
    check s!"metadata retains the {fragment} limitation" (contains metadataScope.compress fragment)
  let definition ← IO.FS.readFile "Formal/Properties/Universal/UP008/Definition.lean"
  let runSource ← IO.FS.readFile "Formal/Properties/Universal/UP008/Run.lean"
  check "native UP-008 uses shared continuation helpers without another property dependency"
    (contains definition "import Formal.Support.Continuations" &&
     !contains definition "Universal.UP011" && !contains runSource "Universal.UP011" &&
     !contains definition "Universal.UP014" && !contains runSource "Universal.UP014" &&
     !contains definition "Universal.UP007" && !contains runSource "Universal.UP007" &&
     !contains definition "CandidateHelpers" && !contains runSource "CandidateHelpers")
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
  let some selected := UP008.run.models.find? (·.id == id.modelId)
    | throw (IO.userError "missing selected model")
  let some model := models.find? (·.runnable.metadata.id == id.modelId)
    | throw (IO.userError "missing native model")
  let nativeMetadata ← IO.ofExcept (TransactionModel.parse model.runnable.metadata.toJson)
  let binding := configured.context.binding
  check "property and model snapshots retain the selected identity"
    (configured.context.propertyDefinition == metadata && binding.txModel == nativeMetadata &&
     binding.combinedCheck.propertyId? == some "UP-008" &&
     binding.combinedCheck.definitionVersion? == some 1 &&
     binding.combinedCheck.txModelId? == some "TxM-007")
  check "every pairing limitation reaches the binding"
    (!selected.limitations.isEmpty &&
     (binding.combinedCheck.toJson.getObjVal? "limitations").toOption ==
       some (toJson selected.limitations))
  let plan ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.UP008").mapError toString)
  let [mainJob, support] := plan.jobs.toList
    | throw (IO.userError "expected one rejection job and one applicability job")
  check "both obligations retain expected-Valid semantics, binding, and scope"
    (plan.propertyDefinition == some metadata && plan.jobs.all fun job =>
      job.expected == .valid && job.propertyId == "UP-008" &&
      job.txModelId == some "TxM-007" && job.binding == some binding &&
      contains job.scope "1,000,000 CEK steps" &&
      contains job.scope "Fuel exhaustion does not establish rejection" &&
      contains job.scope "four guards" && contains job.scope "check applicability separately")
  check "the main obligation links only its own applicability job"
    (mainJob.name == "junkToken_claim" && mainJob.role == .property &&
     support.name == "junkToken_claim_applies" && support.role == .applicability &&
     support.applicability.isNone &&
     mainJob.applicability == some { moduleName := support.moduleName, name := support.name })
  check "both formulas retain acceptance, explicit rejection, and the original bound"
    (mainJob.statement == "Formal.Properties.Universal.UP008.statement validScriptContext (accepts 1000000) (rejects 1000000) claim" &&
     support.statement == "Formal.Properties.Universal.UP008.applicability validScriptContext (accepts 1000000) (rejects 1000000) claim")
  let some types := plan.modules.find? (·.name == "Generated.UP008.Types")
    | throw (IO.userError "missing evaluator module")
  check "the prepared evaluators match the kernel parity formulas"
    (contains types.source "def args (ctx : ScriptContext) : List Term := [toTerm ctx]" &&
     contains types.source s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}" &&
     contains types.source "def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)" &&
     contains types.source "def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=\n  Formal.Support.rejectedWithin program (args ctx) fuel")
  check "the prepared hash is computed from the reference bytes"
    (contains types.source s!"def scriptHashHex : String := {reprStr Formal.Vesting.Linear.Blueprint.scriptHashHex}")
  check "generation uses the unchanged native Claim context builder"
    (plan.modules.any fun source => source.name == "Generated.UP008.Tx" &&
      contains source.source s!"abbrev claim := {model.runnable.context}")
  let some checks := plan.modules.find? (·.name == "Generated.UP008.Checks")
    | throw (IO.userError "missing checks module")
  for (job, definition) in [(mainJob, "statement"), (support, "applicability")] do
    check s!"{job.name}: generated source matches the registered job"
      (contains checks.source s!"theorem {job.name} :\n    {job.statement} := by\n  unfold Formal.Properties.Universal.UP008.{definition}\n  blaster")
  check "generated proofs use native definitions without standalone or Cancel imports"
    (contains checks.source "import Formal.Properties.Universal.UP008.Definition" &&
     contains checks.source "import Formal.Properties.Universal.UP008.Run" &&
     plan.modules.all fun source =>
       !contains source.source "Blueprint.JunkToken" &&
       !contains source.source "Tests.Standalone" &&
       !contains source.source "Universal.UP011" &&
       !contains source.source "Universal.UP014" &&
       !contains source.source "Universal.UP007" &&
       !contains source.source "junkToken_cancel" &&
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
      ("UP-012", (1 : Int), "TxM-007"), ("UP-008", 2, "TxM-007"),
      ("UP-008", 1, "TxM-008"), ("UP-008", 1, "TxM-999")] do
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
    check s!"{modelId} cannot be selected as a native UP-008 pair"
      ((catalogue.loadCheck { id with modelId }).toOption.isNone)
  expectError "Cancel cannot bypass selection through direct generation" .unsupported
    (Workflow.Declarative.generate "UP-008" property cancelModel input.target "Generated.Cancel")
  for invalid in [
      { UP008.run with models := #[{ id := "TxM-999" }] },
      { UP008.run with models := #[{ id := "TxM-007" }, { id := "TxM-007" }] },
      { UP008.run with statement := { UP008.run.statement with definition := ``Nat.add } }] do
    check "unknown models, duplicate selections, and mismatched definitions are rejected"
      (← Catalogue.load #[property invalid] models).toOption.isNone
  check "duplicate model exports are rejected"
    (← Catalogue.load #[property] (models.push model)).toOption.isNone
  IO.println "Declarative UP-008 unit checks passed: Claim registration, parity, applicability links, bindings, and admission controls."

end Formal.Properties.Universal.UP008.Tests

def main : IO Unit := Formal.Properties.Universal.UP008.Tests.unit

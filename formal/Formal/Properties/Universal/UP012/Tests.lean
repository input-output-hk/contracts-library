import Formal.Properties.Universal.UP012.Run
import Formal.TxModels.Definitions.TxM007
import Formal.TxModels.Definitions.TxM008
import Formal.TxModels.Definitions.TxM009
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.UP012.Profile
import Workflow.Tests.Support
import Candidates.Catalogue

namespace Formal.Properties.Universal.UP012.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM007", runnable := TxModels.TxM007.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM008", runnable := TxModels.TxM008.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM009", runnable := TxModels.TxM009.runnable }]

private def property (run : PropertyRun) : Property := {
  run
  runModule := "Formal.Properties.Universal.UP012.Run"
  definitionModule := "Formal.Properties.Universal.UP012.Definition"
  metadataPath := "Formal/Properties/Universal/UP012/metadata.json" }

private def modelUse (id : String) : ModelUse :=
  (UP012.run.models.find? (·.id == id)).getD { id }

private def normalize (statement : String) : String :=
  String.intercalate " " ((statement.replace "1000000" "ledgerFuel").splitOn " "
    |>.filter (!·.isEmpty))

-- The generated literal bound and the existing bound are definitionally identical.
example {A : Type} (accepts rejects : Nat → CardanoLedgerApi.V3.ScriptContext → Prop)
    (context : A → CardanoLedgerApi.V3.ScriptContext) :
    statement CardanoLedgerApi.V3.validScriptContext (accepts 1000000) (rejects 1000000) context ↔
      statement CardanoLedgerApi.V3.validScriptContext (accepts Formal.Universal.Properties.ledgerFuel)
        (rejects Formal.Universal.Properties.ledgerFuel) context := Iff.rfl

def runTests : IO Unit := do
  let reviewed ← IO.ofExcept (← CombinedCheck.read "Formal/Properties/Universal/UP012/Tests/Expected/combined-checks.json")
  let initial := { UP012.run with models := #[modelUse "TxM-007", modelUse "TxM-008"] }
  let before ← IO.ofExcept (← Catalogue.load #[property initial] models)
  check "the property list determines the registry" (before.checks.size == 2)
  let extended := { initial with models := initial.models.push (modelUse "TxM-009") }
  let after ← IO.ofExcept (← Catalogue.load #[property extended] models)
  check "adding only a model name enables the third combination"
    (after.checks.map (·.modelId) == #["TxM-007", "TxM-008", "TxM-009"])
  check "an unlisted model cannot be loaded"
    ((before.loadCheck { propertyId := "UP-012", definitionVersion := 1, modelId := "TxM-009" }).toOption.isNone)
  for (modelId, fixture, selector) in [
      ("TxM-007", "Workflow/Tests/UP012/Inputs/plutus.json", "linear_vesting.linear_vesting"),
      ("TxM-008", "Workflow/Tests/UP012/Inputs/plutus.json", "linear_vesting.linear_vesting"),
      ("TxM-009", "Workflow/Tests/UP001/Inputs/plutus.json", "vault.vault")] do
    let input ← IO.ofExcept ((← Input.read fixture selector).mapError toString)
    let id : CheckId := { propertyId := "UP-012", definitionVersion := 1, modelId }
    let configured ← IO.ofExcept (after.loadCheck id)
    let some expected := reviewed.find? (fun entry => entry.txModelId? == some id.modelId)
      | throw (IO.userError "missing reviewed combination fixture")
    check s!"{id.modelId}: the full reviewed property/model limitations are preserved"
      (configured.context.binding.combinedCheck == expected)
    let previous ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 modelId)
    let plan ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.Experiment").mapError toString)
    let old ← IO.ofExcept ((Generator.generateOne previous input.target "Generated.Experiment").mapError toString)
    check s!"{modelId}: main and applicability jobs preserve identities and formulae"
      (plan.jobs.size == 2 && plan.jobs.size == old.jobs.size &&
       (plan.jobs.zip old.jobs).all fun (current, prior) =>
         current.name == prior.name && normalize current.statement == normalize prior.statement &&
         current.expected == prior.expected && current.role == prior.role &&
         current.applicability == prior.applicability && current.txModelId == prior.txModelId)
    check s!"{modelId}: selected binding and scope are retained"
      (plan.jobs.all fun job => job.binding == some configured.context.binding && !job.scope.isEmpty)
    check s!"{modelId}: actual supplied program is embedded"
      (plan.modules.any fun source =>
        (source.source.splitOn (reprStr input.target.compiledCode)).length == 2)
    let versionError := Generator.generateOne configured { input.target with plutusVersion := "v2" }
      "Generated.Unsupported"
    check s!"{modelId}: unsupported inputs stop before proving" versionError.toOption.isNone
  for invalid in [
      { extended with models := #[modelUse "TxM-999"] },
      { extended with models := #[modelUse "TxM-007", modelUse "TxM-007"] },
      { extended with statement := { extended.statement with definition := ``Nat.add } }] do
    check "bad model names, duplicate selections, and wrong definitions are rejected"
      (← Catalogue.load #[property invalid] models).toOption.isNone
  let some firstModel := models[0]? | throw (IO.userError "missing model fixture")
  check "duplicate model exports are rejected"
    (← Catalogue.load #[property extended] (models.push firstModel)).toOption.isNone
  IO.println "Declarative UP-012 checks passed: list selection, legacy formula parity, metadata, and rejection controls."

end Formal.Properties.Universal.UP012.Tests

def main : IO Unit := Formal.Properties.Universal.UP012.Tests.runTests

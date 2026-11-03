import Formal.Properties.Universal.UP001.Run
import Formal.TxModels.Definitions.TxM001
import Formal.TxModels.Definitions.TxM002
import Formal.TxModels.Definitions.TxM003
import Formal.TxModels.Definitions.TxM004
import Formal.TxModels.Definitions.TxM005
import Formal.TxModels.Definitions.TxM006
import Workflow.Declarative.Catalogue
import Workflow.Input
import Workflow.Tests.Support
import Workflow.Tests.UP001.DefinitionEquivalence
import Workflow.Tests.Legacy.Candidates.UP001

namespace Formal.Properties.Universal.UP001.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def models : Array Model := #[
  { moduleName := "Formal.TxModels.Definitions.TxM001", runnable := TxModels.TxM001.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM002", runnable := TxModels.TxM002.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM003", runnable := TxModels.TxM003.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM004", runnable := TxModels.TxM004.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM005", runnable := TxModels.TxM005.runnable },
  { moduleName := "Formal.TxModels.Definitions.TxM006", runnable := TxModels.TxM006.runnable }]

private def modelUse (id : String) : ModelUse :=
  (UP001.run.models.find? (·.id == id)).getD { id }

private def property : Property := {
  -- This compatibility fixture covers the six original families, independently of new enabled models.
  run := { UP001.run with models := Workflow.Tests.Legacy.Candidates.UP001.modelIds.map modelUse }
  runModule := "Formal.Properties.Universal.UP001.Run"
  definitionModule := "Formal.Properties.Universal.UP001.Definition"
  metadataPath := "Formal/Properties/Universal/UP001/metadata.json" }

private def normalize (statement : String) : String :=
  String.intercalate " " (statement.splitOn " " |>.filter (!·.isEmpty))

def runTests : IO Unit := do
  let reviewed ← IO.ofExcept (← CombinedCheck.read "Formal/Properties/Universal/UP001/Tests/Expected/combined-checks.json")
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] models)
  check "all six purpose models retain their existing registry order"
    (catalogue.checks.map (·.modelId) == Workflow.Tests.Legacy.Candidates.UP001.modelIds)
  check "the reviewed bound and absence of applicability remain explicit"
    (UP001.run.fuel == 5000000 && UP001.run.applicability.isNone)
  let initial := { property with run := { UP001.run with models := #[modelUse "TxM-001"] } }
  let before ← IO.ofExcept (← Catalogue.load #[initial] models)
  let extended := { initial with run := { initial.run with models := initial.run.models.push (modelUse "TxM-006") } }
  let after ← IO.ofExcept (← Catalogue.load #[extended] models)
  check "adding only a model name enables the new combination"
    (before.checks.size == 1 && after.checks.map (·.modelId) == #["TxM-001", "TxM-006"])
  check "unlisted models cannot be loaded"
    ((before.loadCheck { propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-006" }).toOption.isNone)
  let input ← IO.ofExcept ((← Input.read "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault").mapError toString)
  let target := { input.target with handlers := #[] }
  let some handler := input.target.handlers[0]? | throw (IO.userError "missing handler fixture")
  for model in models do
    let id : CheckId := { propertyId := "UP-001", definitionVersion := 1, modelId := model.runnable.metadata.id }
    let configured ← IO.ofExcept (catalogue.loadCheck id)
    let some expected := reviewed.find? (fun entry => entry.txModelId? == some id.modelId)
      | throw (IO.userError "missing reviewed combination fixture")
    check s!"{id.modelId}: the full reviewed property/model limitations are preserved"
      (configured.context.binding.combinedCheck == expected)
    let plan ← IO.ofExcept ((Generator.generateOne configured target "Generated.Parity").mapError toString)
    let prior ← IO.ofExcept ((Workflow.Tests.Legacy.Candidates.UP001.providerForModel id.modelId).mapError toString)
    let old ← IO.ofExcept ((prior.generate target "Generated.Parity").mapError toString)
    let [current] := plan.jobs.toList | throw (IO.userError "expected one generated UP-001 job")
    let [previous] := old.jobs.toList | throw (IO.userError "expected one legacy UP-001 job")
    let nativeName := model.runnable.context.toString.replace "Formal.TxModels." ""
    check s!"{id.modelId}: native family, bound, name, and expected result match the prior generator"
      (current.name == previous.name &&
       normalize current.statement == normalize (previous.statement.replace nativeName "ctx") &&
       current.expected == previous.expected && current.role == previous.role &&
       current.applicability.isNone && current.txModelId == previous.txModelId)
    check s!"{id.modelId}: generated evidence retains the resolved binding"
      (plan.modules.size == 3 && plan.jobs.all (·.binding == some configured.context.binding))
    let some purpose := model.runnable.purpose | throw (IO.userError "missing purpose fixture")
    let declared := { target with handlers := #[{ handler with purpose := some purpose }] }
    let skipped ← IO.ofExcept ((Generator.generateOne configured declared "Generated.Skipped").mapError toString)
    check s!"{id.modelId}: a declared purpose creates no goals or modules"
      (skipped.jobs.isEmpty && skipped.modules.isEmpty &&
       skipped.notes.any (fun note => (note.splitOn "declared handler").length == 2))
    let parameter : ArgumentDescription := { schema := .null, title := none, description := none }
    for unsupported in [
        { declared with plutusVersion := "v2" },
        { declared with parameters := some #[parameter] }] do
      check s!"{id.modelId}: unsupported targets cannot bypass admission through skipping"
        (match Generator.generateOne configured unsupported "Generated.Unsupported" with
         | .error error => error.kind == .unsupported
         | .ok _ => false)
  let some first := models[0]? | throw (IO.userError "missing model fixture")
  let missingPurpose := { first with runnable := { first.runnable with purpose := none } }
  let invalid ← IO.ofExcept (← Catalogue.load #[property] (models.set! 0 missingPurpose))
  let configured ← IO.ofExcept (invalid.loadCheck
    { propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-001" })
  check "a model without purpose metadata is an error, never a skipped or passing proof"
    (match Generator.generateOne configured target "Generated.Invalid" with
     | .error error => error.kind == .invalidPlan
     | .ok _ => false)
  let badName := { property with run := { property.run with theoremSuffix := fun _ => "bad/name" } }
  let invalid ← IO.ofExcept (← Catalogue.load #[badName] models)
  let configured ← IO.ofExcept (invalid.loadCheck
    { propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-001" })
  check "invalid theorem names fail before Lean source generation"
    (Generator.generateOne configured target "Generated.Invalid").toOption.isNone
  IO.println "Declarative UP-001 checks passed: six native families, formula parity, name-only selection, purpose filtering, and admission controls."

end Formal.Properties.Universal.UP001.Tests

def main : IO Unit := Formal.Properties.Universal.UP001.Tests.runTests

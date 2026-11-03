import Formal.Properties.Universal.UP015.Run
import Formal.Properties.Universal.UP015.Tests.Controls
import Formal.Properties.Universal.UP012.Run
import Formal.TxModels.Definitions.TxM007
import Workflow.Declarative.Catalogue
import Workflow.Executor
import Workflow.Input
import Workflow.Reporter
import Workflow.Tests.Support
import Candidates.Catalogue

namespace Formal.Properties.Universal.UP015.Tests

open Lean Workflow Workflow.Declarative Workflow.Tests.Support

private def model : Model := {
  moduleName := "Formal.TxModels.Definitions.TxM007"
  runnable := TxModels.TxM007.runnable }

private def property : Property := {
  run := UP015.run
  runModule := "Formal.Properties.Universal.UP015.Run"
  definitionModule := "Formal.Properties.Universal.UP015.Definition"
  metadataPath := "Formal/Properties/Universal/UP015/metadata.json" }

private def id : CheckId := { propertyId := "UP-015", definitionVersion := 1, modelId := "TxM-007" }
private def fixture := "Workflow/Tests/UP012/Inputs/plutus.json"

private def normalize (text : String) : String :=
  String.intercalate " " ((text.replace "1000000" "ledgerFuel").splitOn " "
    |>.filter (!·.isEmpty))

example {A : Type} (accepts : Nat → CardanoLedgerApi.V3.ScriptContext → Prop)
    (context : A → CardanoLedgerApi.V3.ScriptContext) :
    statement CardanoLedgerApi.V3.validScriptContext (accepts 1000000) context ↔
      statement CardanoLedgerApi.V3.validScriptContext
        (accepts Formal.Universal.Properties.ledgerFuel) context := Iff.rfl

example {A : Type} (accepts : Nat → CardanoLedgerApi.V3.ScriptContext → Prop)
    (context : A → CardanoLedgerApi.V3.ScriptContext) :
    applicability CardanoLedgerApi.V3.validScriptContext (accepts 1000000) context ↔
      applicability CardanoLedgerApi.V3.validScriptContext
        (accepts Formal.Universal.Properties.ledgerFuel) context := Iff.rfl

def unit : IO Unit := do
  let reviewed ← IO.ofExcept (← CombinedCheck.read "Formal/Properties/Universal/UP015/Tests/Expected/combined-checks.json")
  let [expected] := reviewed.toList | throw (IO.userError "missing reviewed combination fixture")
  let catalogue ← IO.ofExcept (← Catalogue.load #[property] #[model])
  check "UP-015 registers using only its property-owned declaration" (catalogue.checks == #[id])
  let configured ← IO.ofExcept (catalogue.loadCheck id)
  check "the full reviewed property/model limitations are preserved"
    (configured.context.binding.combinedCheck == expected)
  let previous ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-015" 1 "TxM-007")
  let input ← IO.ofExcept ((← Input.read fixture "linear_vesting.linear_vesting").mapError toString)
  let generated ← IO.ofExcept ((Generator.generateOne configured input.target "Generated.UP015").mapError toString)
  let old ← IO.ofExcept ((Generator.generateOne previous input.target "Generated.UP015").mapError toString)
  check "the same two obligations, definitions, expectations, models, and support links remain"
    (generated.jobs.size == 2 && generated.jobs.size == old.jobs.size &&
     (generated.jobs.zip old.jobs).all fun (current, prior) =>
       current.name == prior.name && normalize current.statement == normalize prior.statement &&
       current.role == prior.role && current.expected == prior.expected &&
       current.txModelId == prior.txModelId && current.applicability == prior.applicability)
  check "both obligations retain the exact selected binding"
    (generated.jobs.all (·.binding == some configured.context.binding))
  check "the model's existing context builder is imported automatically"
    (generated.modules.any fun source => source.name.endsWith ".Tx" &&
      (source.source.splitOn "abbrev claim := Formal.TxModels.TxM007.claim").length == 2)
  let vault ← IO.ofExcept ((← Input.read "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault").mapError toString)
  match Generator.generateOne configured vault.target "Generated.Unsupported" with
  | .error error => check "the existing model admission boundary remains" (error.kind == .unsupported)
  | .ok _ => throw (IO.userError "UP-015 admitted the unsupported vault/model combination")
  let other : Property := {
    run := { UP012.run with models := UP012.run.models.filter (·.id == "TxM-007") }
    runModule := "Formal.Properties.Universal.UP012.Run"
    definitionModule := "Formal.Properties.Universal.UP012.Definition"
    metadataPath := "Formal/Properties/Universal/UP012/metadata.json" }
  let together ← IO.ofExcept (← Catalogue.load #[other, property] #[model])
  check "different property signatures share the same model and generic catalogue"
    (together.checks.map (·.propertyId) == #["UP-012", "UP-015"])
  let source ← IO.FS.readFile "Formal/Properties/Universal/UP015/Run.lean"
  check "the property run file needs no direct model imports"
    (!(source.splitOn "\n").any (·.startsWith "import Formal.TxModels.Definitions."))
  IO.println "Declarative UP-015 unit checks passed: automatic registration, formula parity, scope, and shared-model selection."

def negativeControl : IO Unit := do
  let input ← IO.ofExcept ((← Input.read fixture "linear_vesting.linear_vesting").mapError toString)
  let control : Property := {
    property with
    run := { UP015.run with
      statement := {
        definition := ``Controls.rejectAfterReverse
        arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
      theoremPrefix := "control_reverseOutputs"
      scope := "TEST ONLY: counterfactual rejection after the Claim output reversal. " ++
        "Preserve the model, validity premises, nonidentity applicability, and 1,000,000-step bound." }
    definitionModule := "Formal.Properties.Universal.UP015.Tests.Controls" }
  let plan ← IO.ofExcept ((generate "UP-015-rejection-control" control model input.target "Generated.Control").mapError toString)
  let execution ← IO.ofExcept (← Executor.run plan {
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    outputRoot := some "output"
    budgetMs := 300000 })
  let report := Reporter.build plan execution
  let some directory := execution.directory | throw (IO.userError "missing control evidence")
  IO.FS.writeFile (directory / "input.json") input.sourceText
  report.write directory
  IO.print report.text
  IO.println s!"Control report: {directory / "report.json"}"
  check "the counterfactual completes with FAIL and no execution problems"
    (execution.state == .completed && execution.problems.isEmpty && report.status == .fail)
  check "the control retains no official property/binding claim"
    (report.propertyDefinition.isNone && report.rows.all (·.job.binding.isNone))
  check "the control contains both required observations" (report.rows.size == 2)
  for row in report.rows do
    if row.job.role == .property then
      check "counterfactual rejection is Falsified/FAIL"
        (row.observed == some .falsified && row.status == .fail)
    else
      check "nonidentity applicability remains Valid/PASS"
        (row.observed == some .valid && row.status == .pass)
  IO.println "Declarative UP-015 negative control passed (the property failure is intentional)."

end Formal.Properties.Universal.UP015.Tests

def main (args : List String) : IO Unit := do
  match args with
  | [] | ["--unit"] => Formal.Properties.Universal.UP015.Tests.unit
  | ["--negative-control"] => Formal.Properties.Universal.UP015.Tests.negativeControl
  | _ => throw (IO.userError "Usage: UP015/Tests.lean --unit|--negative-control")

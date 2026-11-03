import Workflow
import Workflow.Tests.UP015.DefinitionEquivalence
import Workflow.Tests.UP015.Profile
import Workflow.Tests.UP012.Profile
import Workflow.Tests.Support
import Candidates.Catalogue

namespace Workflow.Tests.UP015.Tests

open Lean Workflow Workflow.Generator Workflow.Tests.Support

def run : IO Unit := do
  for (fixture, expectedHash) in [
      ("Workflow/Tests/UP012/Inputs/plutus.json",
       "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a"),
      ("Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json",
       "114e35c85d59745cb61ba73e1a9192467a4dae666a286a45f97a15f8")] do
    let input ← IO.ofExcept ((← Input.read fixture
      "linear_vesting.linear_vesting").mapError toString)
    let plan ← IO.ofExcept ((generate Profile.provider input.target "Generated.Outputs").mapError toString)
    check "UP015 emits three modules and exactly two obligations"
      (plan.modules.size == 3 && plan.jobs.map (·.name) ==
        #["reverseOutputs_claim", "reverseOutputs_claim_applies"])
    check "UP015 uses the existing Claim model and declared Valid expectations"
      (plan.jobs.all fun job => job.txModelId == some "TxM-007" && job.expected == .valid)
    let some main := plan.jobs[0]? | throw (IO.userError "missing UP015 property job")
    let some support := plan.jobs[1]? | throw (IO.userError "missing UP015 applicability job")
    check "UP015 property is explicitly qualified by the nonidentity applicability goal"
      (main.role == .property && support.role == .applicability &&
       main.applicability == some { moduleName := support.moduleName, name := support.name } &&
       support.applicability.isNone)
    check "UP015 generated declarations instantiate the native property"
      (main.statement == "Formal.Properties.Universal.UP015.statement validScriptContext (accepts ledgerFuel) claim" &&
       support.statement == "Formal.Properties.Universal.UP015.applicability validScriptContext (accepts ledgerFuel) claim")
    let signerProvider ← IO.ofExcept ((Workflow.Tests.UP012.Profile.providerForModel "TxM-007").mapError toString)
    let signerPlan ← IO.ofExcept ((generate signerProvider input.target "Generated.Outputs").mapError toString)
    let some types := plan.modules[0]? | throw (IO.userError "missing UP015 types")
    let some tx := plan.modules[1]? | throw (IO.userError "missing UP015 model")
    let some signerTypes := signerPlan.modules[0]? | throw (IO.userError "missing UP012 types")
    let some signerTx := signerPlan.modules[1]? | throw (IO.userError "missing UP012 model")
    check "UP012 and UP015 reuse identical validator and native model preparation"
      (types.source == signerTypes.source && tx.source == signerTx.source)
    check s!"{fixture}: UP015 embeds the exact accepted code and its known hash"
      (((types.source.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr input.target.compiledCode}").length == 2) &&
       ((types.source.splitOn s!"def scriptHashHex : String := {reprStr expectedHash}").length == 2))
    let signerConfigured ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-012" 1 "TxM-007")
    let signerSelected ← IO.ofExcept ((generateOne signerConfigured input.target
      "Generated.Selected").mapError toString)
    check "UP015 only emits the Claim model alias"
      (((tx.source.splitOn "abbrev claim :=").length == 2) &&
       ((tx.source.splitOn "abbrev cancel :=").length == 1))
    let configured ← IO.ofExcept (← Candidates.Catalogue.loadCheck "UP-015" 1 "TxM-007")
    let selected ← IO.ofExcept ((generateOne configured input.target "Generated.Selected").mapError toString)
    check "UP012 and UP015 exact selections prepare identical validator and model modules"
      (signerSelected.modules[0]?.map (·.source) == selected.modules[0]?.map (·.source) &&
       signerSelected.modules[1]?.map (·.source) == selected.modules[1]?.map (·.source))
    check "UP015 exact selection binds every obligation to the official combination"
      (selected.jobs.all fun job => job.binding == some configured.context.binding)
    for model in ["TxM-008", "TxM-unknown"] do
      check "UP015 rejects unsupported model selection"
        ((← Candidates.Catalogue.loadCheck "UP-015" 1 model).toOption.isNone)
    let parameter : ArgumentDescription :=
      { schema := Json.mkObj [("dataType", .str "integer")], title := none, description := none }
    for target in [
        { input.target with compiledCode := "480100002221200101" },
        { input.target with compiledCode := input.target.compiledCode ++ "00" },
        { input.target with parameters := some #[parameter] },
        { input.target with plutusVersion := "v2" },
        { input.target with handlers := #[] }] do
      match generate Profile.provider target "Generated.Unsupported" with
      | .error error => check "UP015 pinned-profile restriction is explicit" (error.kind == .unsupported)
      | .ok _ => throw (IO.userError "UP015 accepted an unsupported target")
  IO.println "UP015 generator and definition checks passed."

end Workflow.Tests.UP015.Tests

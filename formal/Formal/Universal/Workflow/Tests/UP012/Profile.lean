import Formal.Universal.Workflow.Tests.Profiles.LinearVesting
import Formal.Universal.Workflow.Preparation.TxM009
import Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012

namespace Formal.Universal.Workflow.Tests.UP012.Profile

open Formal.Universal.Workflow Formal.Universal.Workflow.Generator

/-! Pinned vesting and structurally admitted TxM-009 targets share the UP-012 goals.
Preparation emits the actual program and native transaction aliases.
-/

private def buildSelected (target : TargetDescription) (modulePrefix : String)
    (selectedModelId : Option String) : Except Error GenerationPlan := do
  let (modules, modelId) ← match selectedModelId with
    | some modelId => do
      let modules ← if modelId == Formal.Universal.TxModels.TxM009.metadata.id then
          Formal.Universal.Workflow.Preparation.TxM009.support target modulePrefix
        else Formal.Universal.Workflow.Tests.Profiles.LinearVesting.support target modulePrefix (some modelId)
      pure (modules, some modelId)
    | none =>
      match Formal.Universal.Workflow.Preparation.TxM009.support target modulePrefix with
      | .ok modules => pure (modules, some Formal.Universal.TxModels.TxM009.metadata.id)
      | .error vaultError =>
        unless vaultError.kind == .unsupported do throw vaultError
        match Formal.Universal.Workflow.Tests.Profiles.LinearVesting.support target modulePrefix none with
        | .ok modules => pure (modules, none)
        | .error vestingError =>
          throw ⟨.unsupported, s!"{vestingError.message}; {vaultError.message}"⟩
  let checks ← match modelId with
    | none => pure (Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.checks modulePrefix)
    | some id => Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.checksForModel id modulePrefix
  let jobs ← match modelId with
    | none => pure (Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.jobs modulePrefix)
    | some id => Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.jobsForModel id modulePrefix
  return {
    targetName := target.name
    modules := modules.push checks
    jobs
    notes := match modelId with
      | none => Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.notes
      | some id => Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.notesForModel id }

/-- Select reusable spending preparation or the existing pinned vesting scenario. -/
def provider : Provider := { id := "UP-012", generate := fun target modulePrefix => buildSelected target modulePrefix none }

/-- Bind one native model to its supported preparation path. -/
def providerForModel (selectedModelId : String) : Except Error Provider := do
  unless Formal.Universal.Workflow.Tests.Legacy.Candidates.UP012.modelIds.contains selectedModelId do
    throw ⟨.unsupported, s!"UP-012 has no registered model {selectedModelId}"⟩
  return { id := "UP-012", generate := fun target modulePrefix => buildSelected target modulePrefix (some selectedModelId) }

end Formal.Universal.Workflow.Tests.UP012.Profile

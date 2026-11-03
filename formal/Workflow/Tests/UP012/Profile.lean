import Workflow.Tests.Profiles.LinearVesting
import Workflow.Preparation.TxM009
import Candidates.UP012

namespace Workflow.Tests.UP012.Profile

open Workflow Workflow.Generator

/-! Pinned vesting and structurally admitted TxM-009 targets share the UP-012 goals.
Preparation emits the actual program and native transaction aliases.
-/

private def buildSelected (target : TargetDescription) (modulePrefix : String)
    (selectedModelId : Option String) : Except Error GenerationPlan := do
  let (modules, modelId) ← match selectedModelId with
    | some modelId => do
      let modules ← if modelId == Formal.TxModels.TxM009.metadata.id then
          Workflow.Preparation.TxM009.support target modulePrefix
        else Workflow.Tests.Profiles.LinearVesting.support target modulePrefix (some modelId)
      pure (modules, some modelId)
    | none =>
      match Workflow.Preparation.TxM009.support target modulePrefix with
      | .ok modules => pure (modules, some Formal.TxModels.TxM009.metadata.id)
      | .error vaultError =>
        unless vaultError.kind == .unsupported do throw vaultError
        match Workflow.Tests.Profiles.LinearVesting.support target modulePrefix none with
        | .ok modules => pure (modules, none)
        | .error vestingError =>
          throw ⟨.unsupported, s!"{vestingError.message}; {vaultError.message}"⟩
  let checks ← match modelId with
    | none => pure (Candidates.UP012.checks modulePrefix)
    | some id => Candidates.UP012.checksForModel id modulePrefix
  let jobs ← match modelId with
    | none => pure (Candidates.UP012.jobs modulePrefix)
    | some id => Candidates.UP012.jobsForModel id modulePrefix
  return {
    targetName := target.name
    modules := modules.push checks
    jobs
    notes := match modelId with
      | none => Candidates.UP012.notes
      | some id => Candidates.UP012.notesForModel id }

/-- Select reusable spending preparation or the existing pinned vesting scenario. -/
def provider : Provider := { id := "UP-012", generate := fun target modulePrefix => buildSelected target modulePrefix none }

/-- Bind one native model to its supported preparation path. -/
def providerForModel (selectedModelId : String) : Except Error Provider := do
  unless Candidates.UP012.modelIds.contains selectedModelId do
    throw ⟨.unsupported, s!"UP-012 has no registered model {selectedModelId}"⟩
  return { id := "UP-012", generate := fun target modulePrefix => buildSelected target modulePrefix (some selectedModelId) }

end Workflow.Tests.UP012.Profile

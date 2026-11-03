import Candidates.UP015
import Workflow.Tests.Profiles.LinearVesting

namespace Workflow.Tests.UP015.Profile

open Workflow Workflow.Generator

private def generate (target : TargetDescription) (modulePrefix : String) :
    Except Error GenerationPlan := do
  let modules ← Profiles.LinearVesting.support target modulePrefix (some "TxM-007")
  return {
    targetName := target.name
    modules := modules.push (Candidates.UP015.checks modulePrefix)
    jobs := Candidates.UP015.jobs modulePrefix
    notes := Candidates.UP015.notes }

/-- A scoped test profile for one reversal of the pinned vesting Claim's two outputs. -/
def provider : Provider := { id := "UP-015", generate }

def providerForModel (modelId : String) : Except Error Provider := do
  unless Candidates.UP015.modelIds.contains modelId do
    throw ⟨.unsupported, s!"UP-015 has no registered model {modelId}"⟩
  return provider

end Workflow.Tests.UP015.Profile

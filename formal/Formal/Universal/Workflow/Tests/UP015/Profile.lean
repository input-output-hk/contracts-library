import Formal.Universal.Workflow.Tests.Legacy.Candidates.UP015
import Formal.Universal.Workflow.Tests.Profiles.LinearVesting

namespace Formal.Universal.Workflow.Tests.UP015.Profile

open Formal.Universal.Workflow Formal.Universal.Workflow.Generator

private def generate (target : TargetDescription) (modulePrefix : String) :
    Except Error GenerationPlan := do
  let modules ← Profiles.LinearVesting.support target modulePrefix (some "TxM-007")
  return {
    targetName := target.name
    modules := modules.push (Formal.Universal.Workflow.Tests.Legacy.Candidates.UP015.checks modulePrefix)
    jobs := Formal.Universal.Workflow.Tests.Legacy.Candidates.UP015.jobs modulePrefix
    notes := Formal.Universal.Workflow.Tests.Legacy.Candidates.UP015.notes }

/-- A scoped test profile for one reversal of the pinned vesting Claim's two outputs. -/
def provider : Provider := { id := "UP-015", generate }

def providerForModel (modelId : String) : Except Error Provider := do
  unless Formal.Universal.Workflow.Tests.Legacy.Candidates.UP015.modelIds.contains modelId do
    throw ⟨.unsupported, s!"UP-015 has no registered model {modelId}"⟩
  return provider

end Formal.Universal.Workflow.Tests.UP015.Profile

import Formal.Properties.Universal.UP000.Definition
import Workflow.Declarative.Types
import Formal.TxModels.Artifacts.LinearVesting

namespace Formal.Properties.Universal.UP000

open Workflow Workflow.Declarative

private def skipOutsideReferenceArtifact (target : TargetDescription) (_model : Model) :
    Except Generator.Error (Option String) := do
  if target.compiledCode == Formal.TxModels.Artifacts.LinearVesting.referenceCompiledCode then
    return none
  return some "UP-000 requires the reference linear-vesting compiled artifact; the selected program is outside this property's pinned scope."

/-- Each selected action supplies its own existence obligation and witness. -/
def run : PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Covers Claim for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-000.",
      "Claim has two inputs, two outputs, one signer, and one vested asset under fixed policyA. Symbolic fields vary within that shape; this does not cover arbitrary transactions or enumerate every blueprint action.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability.",
      "The check adds no minimum of 1 ADA per output and prints no accepted transaction witness. A FAIL is scoped to this model and CEK bound; it does not by itself establish that funds are stuck."] },
    { id := "TxM-008", limitations := #[
      "Covers Cancel for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-000.",
      "Cancel has two inputs, one output, one signer, and one vested asset under fixed policyA. Symbolic fields vary within that shape; this does not cover arbitrary transactions or enumerate every blueprint action.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability.",
      "The check adds no minimum of 1 ADA per output and prints no accepted transaction witness. A FAIL is scoped to this model and CEK bound; it does not by itself establish that funds are stuck."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  theoremPrefix := "someAccepted"
  fuel := 1000000
  skipReason := skipOutsideReferenceArtifact
  scope := "Require an accepted model-valid context for each selected Claim or Cancel model within 1,000,000 CEK steps. " ++
    "The existential statement includes its witness; there is no separate applicability obligation. " ++
    "This establishes bounded model-valid existence, not full ledger reachability or arbitrary blueprint action coverage. " ++
    "The CEK bound is not a ledger CPU or memory budget." }

end Formal.Properties.Universal.UP000

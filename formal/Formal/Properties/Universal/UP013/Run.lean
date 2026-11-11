import Formal.Properties.Universal.UP013.Definition
import Workflow.Declarative.Types
import Formal.TxModels.Artifacts.LinearVesting

namespace Formal.Properties.Universal.UP013

open Workflow Workflow.Declarative

private def skipOutsideReferenceArtifact (target : TargetDescription) (_model : Model) :
    Except Generator.Error (Option String) := do
  if target.compiledCode == Formal.TxModels.Artifacts.LinearVesting.referenceCompiledCode then
    return none
  return some "UP-013 requires the reference linear-vesting compiled artifact; the selected program is outside this property's pinned scope."

/-- Each selected action supplies a rejection obligation and a separate applicability witness. -/
def run : PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Covers time-sensitive Claim for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-013; fully unbounded-range rejection is not a universal requirement for all validators.",
      "Claim has two inputs, two outputs, one signer, and one vested asset under fixed policyA. Its baseline range has a finite lower bound and no upper bound. Symbolic fields vary within that shape; arbitrary transactions are not covered.",
      "Only the validity range changes, to (-infinity, +infinity). This does not quantify over every range with a missing lower bound. Applicability separately requires a valid accepted baseline and a valid changed context.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability. Rejection means an error or a non-unit halt within the CEK bound; fuel exhaustion does not count."] },
    { id := "TxM-008", limitations := #[
      "Covers time-sensitive Cancel for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-013; fully unbounded-range rejection is not a universal requirement for all validators.",
      "Cancel has two inputs, one output, one signer, and one vested asset under fixed policyA. Its baseline range has a finite lower bound and no upper bound. Symbolic fields vary within that shape; arbitrary transactions are not covered.",
      "Only the validity range changes, to (-infinity, +infinity). This does not quantify over every range with a missing lower bound. Applicability separately requires a valid accepted baseline and a valid changed context.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability. Rejection means an error or a non-unit halt within the CEK bound; fuel exhaustion does not count."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  theoremPrefix := "unboundedRange"
  fuel := 1000000
  skipReason := skipOutsideReferenceArtifact
  scope := "For each selected Claim or Cancel model, replace only the validity range with (-infinity, +infinity). " ++
    "If the baseline is model-valid and accepted and the changed context is model-valid, require explicit rejection within 1,000,000 CEK steps. " ++
    "Each action has a separate applicability obligation witnessing those three premises. " ++
    "This checks time-sensitive actions of the reference linear-vesting artifact; it is not a universal requirement for all validators. " ++
    "It does not cover every range without a lower bound, arbitrary transactions, or full ledger reachability. " ++
    "Fuel exhaustion does not establish rejection, and the CEK bound is not a ledger CPU or memory budget." }

end Formal.Properties.Universal.UP013

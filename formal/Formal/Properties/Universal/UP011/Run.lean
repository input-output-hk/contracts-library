import Formal.Properties.Universal.UP011.Definition
import Workflow.Declarative.Types
import Formal.TxModels.Artifacts.LinearVesting

namespace Formal.Properties.Universal.UP011

open Workflow Workflow.Declarative

private def skipOutsideReferenceArtifact (target : TargetDescription) (_model : Model) :
    Except Generator.Error (Option String) := do
  if target.compiledCode == Formal.TxModels.Artifacts.LinearVesting.referenceCompiledCode then
    return none
  return some "UP-011 requires the reference linear-vesting compiled artifact; the selected program is outside this property's pinned scope."

/-- Claim supplies a rejection obligation and a separate witness to all five applicability guards. -/
def run : PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Covers Claim for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-011. Cancel has no native binding; its standalone applicability observation remains inapplicable.",
      "Claim has two inputs, two outputs, one signer, and one vested asset under fixed policyA. Its first output continues the script with an inline datum; the second pays the signer. Symbolic fields vary within that shape; arbitrary transactions are not covered.",
      "The mutation changes only the first continuation's payment credential, preserving its staking credential, datum, value, and other fields. Continuations match the spent input's payment credential only; this does not establish the full address rule or arbitrary output-order coverage.",
      "The redirect guard changes every matching output's entire address to the fixed attacker key address and removes its datum. Rejection after this combined address-and-datum change does not independently prove address reliance. Applicability witnesses all five original guards, including redirect rejection and the explicit credential inequality guard.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability. Acceptance and explicit rejection use 1,000,000 CEK steps; fuel exhaustion does not establish rejection."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  theoremPrefix := "continuationElsewhere"
  fuel := 1000000
  skipReason := skipOutsideReferenceArtifact
  scope := "For Claim, replace only the first continuation's payment credential with a different credential. " ++
    "Require a model-valid accepted baseline, explicit rejection after redirecting its continuations and removing their datums, " ++
    "the original first-continuation credential inequality guard, and a model-valid changed context. " ++
    "Under these five guards, require explicit rejection within 1,000,000 CEK steps; check applicability separately. " ++
    "The redirect guard combines address and datum changes and does not independently establish address reliance. " ++
    "This covers the reference linear-vesting Claim artifact and fixed model only, not the full address rule, arbitrary transactions, or full ledger reachability. " ++
    "Fuel exhaustion does not establish rejection, and the CEK bound is not a ledger CPU or memory budget." }

end Formal.Properties.Universal.UP011

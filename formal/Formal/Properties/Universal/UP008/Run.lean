import Formal.Properties.Universal.UP008.Definition
import Workflow.Declarative.Types
import Formal.TxModels.Artifacts.LinearVesting

namespace Formal.Properties.Universal.UP008

open Workflow Workflow.Declarative

private def skipOutsideReferenceArtifact (target : TargetDescription) (_model : Model) :
    Except Generator.Error (Option String) := do
  if target.compiledCode == Formal.TxModels.Artifacts.LinearVesting.referenceCompiledCode then
    return none
  return some "UP-008 requires the reference linear-vesting compiled artifact; the selected program is outside this property's pinned scope."

/-- Claim supplies a rejection obligation and a separate witness to all four applicability guards. -/
def run : PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Covers Claim for the reference linear-vesting compiled artifact only. The second artifact admitted by the shared model is skipped for UP-008. Cancel has no native binding; its standalone applicability observation remains inapplicable.",
      "Claim has two inputs, two outputs, one signer, and one vested asset under fixed policyA. Its first output continues the script with an inline datum; the second pays the signer. Symbolic fields vary within that shape; arbitrary transactions are not covered.",
      "The mutation appends an input at unrelatedKey funding the lovelace amount a and one unit of the fixed zzzzjunk/zzzzjunk asset. It appends an output at unrelatedKey returning that lovelace and appends the junk asset to only the first continuation's value. The quantified a : Int is lovelace, not token quantity or count. The changed Claim has three inputs and three outputs.",
      "Continuations match the spent input's payment credential only. The first continuation's address, datum, and reference script are preserved, as are all original inputs and other original outputs. This does not establish arbitrary output-order coverage, multiple-continuation coverage, or a configurable limit on distinct output tokens.",
      "The redirect guard changes every matching output's entire address to the fixed attacker key address and removes its datum. Rejection after this combined address-and-datum change does not independently prove reliance on a continuation's value or rejection of extra assets. Applicability witnesses all four original guards, including redirect rejection and changed-context validity.",
      "The script credential p.script remains symbolic and is not constrained to the supplied program's hash. Model validity does not establish full ledger reachability. Acceptance and explicit rejection use 1,000,000 CEK steps; fuel exhaustion does not establish rejection.",
      "Both native obligations expect Valid. Reproducing the historical original Claim pair of Falsified rejection and Valid applicability yields an official FAIL. This is an artifact/model result and does not by itself establish token flooding, locked funds, a vulnerability, or a token-count limit. The compiled enforcing control remains test-only; issue #29's configurable token-count limit and broader work in issue #96 remain open."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  theoremPrefix := "junkToken"
  fuel := 1000000
  skipReason := skipOutsideReferenceArtifact
  scope := "For Claim, append an unrelated input funding one unit of the fixed zzzzjunk/zzzzjunk asset and the lovelace amount a, " ++
    "append a separate unrelated output returning that lovelace, and append the junk asset to only the first continuation's value. " ++
    "The quantified a : Int is lovelace, not token quantity or count. " ++
    "Require a model-valid accepted baseline, explicit rejection after redirecting its continuations and removing their datums, " ++
    "and a model-valid changed context. Under these four guards, require explicit rejection within 1,000,000 CEK steps; check applicability separately. " ++
    "The redirect guard combines address and datum changes and does not independently establish reliance on continuation value or rejection of extra assets. " ++
    "This covers the reference linear-vesting Claim artifact and fixed model only, not a configurable token-count limit, arbitrary transactions, or full ledger reachability. " ++
    "Fuel exhaustion does not establish rejection, and the CEK bound is not a ledger CPU or memory budget. " ++
    "Both native obligations expect Valid; the historical Falsified/Valid Claim pair remains an official FAIL, not a token-flooding, funds-locking, or vulnerability finding. " ++
    "The compiled enforcing control is test-only. Issue #29's configurable token-count limit and broader work in issue #96 remain open." }

end Formal.Properties.Universal.UP008

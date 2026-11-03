import Formal.Properties.Universal.UP012.Definition
import Workflow.Declarative.Types

namespace Formal.Properties.Universal.UP012

/-- The model list is the only property/model integration point. -/
def run : Workflow.Declarative.PropertyRun := {
  models := #[
    { id := "TxM-007", limitations := #[
      "Experimental pinned linear-vesting Claim profile only; this check does not establish general authorization safety.",
      "Covers one-signer, one-asset baseline Claim contexts with the model's fixed input and output shapes, not multi-signer or multi-asset claims.",
      "Example assumption: the sole baseline signer is intended to satisfy Claim's signature requirement; there are no unrelated extra signers. The tool does not infer that requirement or establish that the signer is the correct owner. General required-signer semantics remain open in issue #33.",
      "The property removes the sole signer to derive a context outside the baseline model family. Its explicit validScriptContext premises and applicability witness do not establish full ledger reachability."] },
    { id := "TxM-008", limitations := #[
      "Experimental pinned linear-vesting Cancel profile only; this check does not establish general authorization safety.",
      "Covers one-signer, one-asset baseline Cancel contexts with the model's fixed input and output shapes, not multi-signer or multi-asset cancellations.",
      "Example assumption: the sole baseline signer is intended to satisfy Cancel's signature requirement; there are no unrelated extra signers. The tool does not infer that requirement or establish that the signer is the correct owner. General required-signer semantics remain open in issue #33.",
      "The property removes the sole signer to derive a context outside the baseline model family. Its explicit validScriptContext premises and applicability witness do not establish full ledger reachability."] },
    { id := "TxM-009", limitations := #[
      "Experimental reusable admission for unparameterized Plutus V3 targets with exactly one declared spending handler and compatible datum/redeemer encodings. Unsupported, missing, unresolved, or ambiguous schema constraints produce SKIPPED with a reason. Structural admission does not infer security roles or establish general authorization safety.",
      "Covers one script input, one public-key output, ADA only, a one-field owner-bytes inline datum, a fixed empty constructor redeemer, and exactly one baseline signer. Other transaction geometries, asset layouts, and datum/redeemer encodings are not covered.",
      "Example assumption: the baseline contains only the intended required signer, with no unrelated extras. Owner, signer, and recipient vary independently; this model does not impose owner equality or infer which key the protocol ought to require.",
      "The property removes the sole signer and requires explicit rejection within 1,000,000 CEK steps. Applicability separately requires a model-valid accepted original and a model-valid changed context. These premises do not establish full ledger reachability or correct-owner authorization."] }]
  statement := {
    definition := ``statement
    arguments := #["validScriptContext", "(accepts {fuel})", "(rejects {fuel})"] }
  applicability := some {
    definition := ``applicability
    arguments := #["validScriptContext", "(accepts {fuel})"] }
  theoremPrefix := "dropSigner"
  fuel := 1000000
  scope := "Remove the first signer in the selected model; preserve validScriptContext premises. " ++
    "Require explicit rejection within 1,000,000 CEK steps. Applicability is checked separately. " ++
    "This does not establish correct-owner authorization or arbitrary transaction coverage." }

end Formal.Properties.Universal.UP012

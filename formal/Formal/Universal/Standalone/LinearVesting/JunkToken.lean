-- Original UP-008 statements from candidate 0e5fb61, preserved as propositions.
-- Solver checks, including the expected falsifications, are in Formal/Universal/Properties/UP008/Tests/Standalone/Checks.lean.
import Formal.Universal.Support.CandidateHelpers
import Formal.Universal.Standalone.LinearVesting.Types
import Formal.Universal.Standalone.LinearVesting.Tx

namespace Formal.Universal.Standalone.LinearVesting

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef validScriptContext)
open Formal.Universal.Support

/-- A `claim` transaction with a junk token, from a new input, appended to its first output back
    to the script is rejected (for transactions that need their outputs back to the script:
    with those sent to another key, they are rejected). -/
def junkToken_claim : Prop :=
    ∀ p (r : TxOutRef) (a : Int),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      validScriptContext (addJunkFrom (claim p) r a) = true →
      rejects ledgerFuel (addJunkFrom (claim p) r a)

/-- `junkToken_claim` applies: some valid accepted `claim` transaction gives a valid changed
    transaction, so the check above does not hold only vacuously. -/
def junkToken_claim_applies : Prop :=
    ∃ p, ∃ (r : TxOutRef), ∃ (a : Int),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      validScriptContext (addJunkFrom (claim p) r a) = true

/-- A `cancel` transaction with a junk token, from a new input, appended to its first output back
    to the script is rejected (for transactions that need their outputs back to the script:
    with those sent to another key, they are rejected). -/
def junkToken_cancel : Prop :=
    ∀ p (r : TxOutRef) (a : Int),
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      rejects ledgerFuel (redirectContinuations (cancel p)) →
      validScriptContext (addJunkFrom (cancel p) r a) = true →
      rejects ledgerFuel (addJunkFrom (cancel p) r a)

/-- `junkToken_cancel` applies: some valid accepted `cancel` transaction gives a valid changed
    transaction, so the check above does not hold only vacuously. -/
def junkToken_cancel_applies : Prop :=
    ∃ p, ∃ (r : TxOutRef), ∃ (a : Int),
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      rejects ledgerFuel (redirectContinuations (cancel p)) ∧
      validScriptContext (addJunkFrom (cancel p) r a) = true

end Formal.Universal.Standalone.LinearVesting

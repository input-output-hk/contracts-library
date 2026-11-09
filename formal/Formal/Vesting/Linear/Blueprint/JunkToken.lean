-- Original UP-008 statements from candidate 0e5fb61, preserved as propositions.
-- Solver checks, including the expected falsifications, are in tests/UP008/Checks.lean.
import Formal.Support.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

namespace Formal.Vesting.Linear.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef validScriptContext)
open Formal.Support

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

end Formal.Vesting.Linear.Blueprint

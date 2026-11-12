-- Standalone UP-011 propositions extracted from the generated blueprint checks.
-- Solver observations live in Formal/Properties/Universal/UP011/Tests/Standalone/Checks.lean, including inapplicable Cancel.
import Formal.Support.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

namespace Formal.Vesting.Linear.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef validScriptContext)
open Formal.Support

/-- A `claim` transaction whose first output back to the script gets another payment credential
    is rejected (for transactions that need their outputs back to the script: with those sent
    to another key without their datums, they are rejected). Staking is unchanged. -/
def continuationElsewhere_claim : Prop :=
    ∀ p (c : Credential),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressCredential == c) = false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true →
      rejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } }))

/-- `continuationElsewhere_claim` applies: some valid accepted `claim` transaction gives a valid
    changed transaction, so the check above does not hold only vacuously. -/
def continuationElsewhere_claim_applies : Prop :=
    ∃ p, ∃ (c : Credential),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressCredential == c) = false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true

/-- A `cancel` transaction whose first output back to the script gets another payment credential
    is rejected (for transactions that need their outputs back to the script: with those sent
    to another key without their datums, they are rejected). Staking is unchanged. -/
def continuationElsewhere_cancel : Prop :=
    ∀ p (c : Credential),
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      rejects ledgerFuel (redirectContinuations (cancel p)) →
      (firstContinuation? (cancel p)).any (fun o => o.txOutAddress.addressCredential == c) = false →
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true →
      rejects ledgerFuel (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } }))

/-- Applicability question for Cancel. The fixed Cancel model has no continuation,
    so the expected observation is Falsified; its implication provides no coverage. -/
def continuationElsewhere_cancel_applies : Prop :=
    ∃ p, ∃ (c : Credential),
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      rejects ledgerFuel (redirectContinuations (cancel p)) ∧
      (firstContinuation? (cancel p)).any (fun o => o.txOutAddress.addressCredential == c) = false ∧
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressCredential := c } })) = true

end Formal.Vesting.Linear.Blueprint

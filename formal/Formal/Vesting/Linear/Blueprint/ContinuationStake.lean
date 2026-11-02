-- Standalone UP-007 obligations for the frozen linear-vesting fixture.
-- Definitions retain the original propositions; tests/UP007/Checks.lean runs them.
import Formal.Universal.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

namespace Formal.Vesting.Linear.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef validScriptContext)
open Formal.Universal.Properties

/-- A `claim` transaction whose first output back to the script gets another staking credential
    is rejected (for transactions that need their outputs back to the script: with those sent
    to another key, they are rejected). -/
def continuationStake_claim : Prop :=
    ∀ p (sc : Option StakingCredential),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true →
      rejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }))

/-- `continuationStake_claim` applies: some valid accepted `claim` transaction gives a valid
    changed transaction, so the check above does not hold only vacuously. -/
def continuationStake_claim_applies : Prop :=
    ∃ p, ∃ (sc : Option StakingCredential),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true

/-- A `cancel` transaction whose first output back to the script gets another staking credential
    is rejected (for transactions that need their outputs back to the script: with those sent
    to another key, they are rejected). -/
def continuationStake_cancel : Prop :=
    ∀ p (sc : Option StakingCredential),
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      rejects ledgerFuel (redirectContinuations (cancel p)) →
      (firstContinuation? (cancel p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false →
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true →
      rejects ledgerFuel (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } }))

/-- `continuationStake_cancel` applies: some valid accepted `cancel` transaction gives a valid
    changed transaction, so the check above does not hold only vacuously. -/
def continuationStake_cancel_applies : Prop :=
    ∃ p, ∃ (sc : Option StakingCredential),
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      rejects ledgerFuel (redirectContinuations (cancel p)) ∧
      (firstContinuation? (cancel p)).any (fun o => o.txOutAddress.addressStakingCredential == sc) =
        false ∧
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutAddress := { o.txOutAddress with addressStakingCredential := sc } })) = true

end Formal.Vesting.Linear.Blueprint

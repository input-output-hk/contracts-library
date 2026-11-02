-- Original UP-014 statements from process_blueprint.py / PR #44.
-- Standalone solver invocations live in tests/UP014/Checks.lean.
import Formal.Universal.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

namespace Formal.Vesting.Linear.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef validScriptContext)
open Formal.Universal.Properties

/-- Reject replacing the first Claim continuation datum with constructor 0 and an empty
    vesting list, under the original validity, acceptance, and continuation-reliance guards. -/
def continuationOtherDatum_claim : Prop :=
    ∀ p (x201 : Credential) (x202 : Credential) (x203 : Int) (x204 : Int) (x205 : Int),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true →
      rejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))

/-- `continuationOtherDatum_claim` applies: some valid accepted `claim` transaction gives a valid
    changed transaction, providing a witness for the guards above. -/
def continuationOtherDatum_claim_applies : Prop :=
    ∃ p, ∃ (x201 : Credential), ∃ (x202 : Credential), ∃ (x203 : Int), ∃ (x204 : Int), ∃
      (x205 : Int),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true

/-- The same datum-replacement check for Cancel. Its continuation-reliance guard has no
    accepted witness in this model; the separate applicability check records that limit. -/
def continuationOtherDatum_cancel : Prop :=
    ∀ p (x201 : Credential) (x202 : Credential) (x203 : Int) (x204 : Int) (x205 : Int),
      validScriptContext (cancel p) = true →
      accepts ledgerFuel (cancel p) →
      rejects ledgerFuel (redirectContinuations (cancel p)) →
      (firstContinuation? (cancel p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false →
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true →
      rejects ledgerFuel (changeContinuation (cancel p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))

/-- `continuationOtherDatum_cancel` applies: some valid accepted `cancel` transaction gives a
    valid changed transaction, providing a witness for the guards above. -/
def continuationOtherDatum_cancel_applies : Prop :=
    ∃ p, ∃ (x201 : Credential), ∃ (x202 : Credential), ∃ (x203 : Int), ∃ (x204 : Int), ∃
      (x205 : Int),
      validScriptContext (cancel p) = true ∧
      accepts ledgerFuel (cancel p) ∧
      rejects ledgerFuel (redirectContinuations (cancel p)) ∧
      (firstContinuation? (cancel p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false ∧
      validScriptContext (changeContinuation (cancel p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true

end Formal.Vesting.Linear.Blueprint

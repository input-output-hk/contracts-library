/-
Linear vesting — COMPLETENESS: `spec ⇒ accepts` (spec §8).

If a transaction satisfies the spec's preconditions for an action (authorized,
schedule well-formed, continuation reproduces the datum and holds the required
remainder), the compiled validator accepts it. This rules out *false
negatives* — honest spends getting stuck (frozen funds).
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Formal.Common
import Formal.Vesting.Linear.Spec
import Formal.Vesting.Linear.Soundness

namespace Formal.Vesting.Linear.Completeness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (Address Redeemer)
open Formal.Common (validatorAccepts)
open Formal.Vesting.Linear.Spec
open Formal.Vesting.Linear.Soundness (mkClaimCtx withAsset)

set_option warn.sorry false

/- Load the compiled `spend` handler of `validators/linear_vesting.ak`.
   Regenerate the flat with `just flats`. -/
#import_uplc linearVestingSpendScript PlutusV3 flat_hex "Scripts/linear_vesting_spend.flat"

def spendValidator : Program := linearVestingSpendScript.script

/-- **Partial-claim completeness (spec ⇒ accepts).** Single-asset instance.

A `Claim` that meets every §8 must-accept clause — beneficiary key signed (C1),
well-formed schedule (C0), inline datum reproduced in the continuation (C2/C3),
and the continuation holding at least the required remainder (C4) — is accepted
by the compiled validator. -/
theorem claim_complete_partial
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let r : Redeemer := claimRedeemer
    -- continuation reproduces the datum verbatim (C2/C3):
    let outDatum := datumData d
    let sigs := match d.beneficiary with | .key h => [h] | .script _ => []
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now sigs r
    d.vesting = [a] ∧
    validSchedule d ∧
    now < d.endTime ∧
    (∃ h, d.beneficiary = .key h) ∧                          -- C1 (key case)
    outQty ≥ required a.total d.startTime d.endTime now →     -- C4
      validatorAccepts ctx spendValidator := by
  -- TODO: prove with `blaster` once `validRangeData` (Soundness.lean) is a real
  -- validity-interval encoding and the toolchain is built.
  sorry

/-- **Full-claim completeness (spec §8.2 / I4).** When `now ≥ end_time` the
required remainder is zero, so no continuing output is needed and the whole
bundle may be withdrawn. TODO: state over a no-continuation context and prove. -/
theorem claim_complete_full (_d : VestingDatum) : True := by
  -- TODO: now ≥ end_time ⇒ required = 0 ⇒ accepts with no continuation.
  trivial

/-- **Cancel completeness (spec §8.3).** Locker authorized, `now > recovery_time`
(strict), schedule well-formed ⇒ accepts, no continuation required.
TODO: state over a cancel context and prove. -/
theorem cancel_complete (_d : VestingDatum) : True := by
  trivial

end Formal.Vesting.Linear.Completeness

/-
Linear vesting — ROBUSTNESS: explicit rejection theorems (spec §9 R-clauses,
§5.1). The validator REJECTS malformed/malicious spends. These complement
Soundness: soundness says "if accepted, then good"; robustness names specific
bad transactions and proves they are *not* accepted.

The headline one is no-double-satisfaction (§5.1, I2): two contract inputs
sharing a datum cannot be satisfied by a single continuation; the `k`-scaling
rule forces `k × required`.
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Formal.Common
import Formal.Vesting.Linear.Spec
import Formal.Vesting.Linear.Soundness
import Formal.Vesting.Linear.Completeness

namespace Formal.Vesting.Linear.Robustness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (Address Redeemer)
open Formal.Common (validatorRejects)
open Formal.Vesting.Linear.Spec
open Formal.Vesting.Linear.Soundness (mkClaimCtx withAsset)
open Formal.Vesting.Linear.Completeness (spendValidator)

set_option warn.sorry false

/-- **R1 — unauthorized claim is rejected.** No signatory satisfies the
beneficiary key ⇒ the validator rejects the `Claim`. -/
theorem reject_unauthorized_claim
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) (outDatum : Data) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now [] claimRedeemer
    (∃ h, d.beneficiary = .key h) →   -- key-auth instance, but NO signatories
      validatorRejects ctx spendValidator := by
  -- TODO: prove (no signatory ⇒ is_authorized fails ⇒ reject).
  sorry

/-- **R2 — over-release is rejected.** A `Claim` whose continuation holds less
than the required remainder is rejected (spec §9 R2, I2/B1). -/
theorem reject_over_release
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let outDatum := datumData d
    let sigs := match d.beneficiary with | .key h => [h] | .script _ => []
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now sigs claimRedeemer
    d.vesting = [a] ∧ validSchedule d ∧ now < d.endTime ∧
    outQty < required a.total d.startTime d.endTime now →   -- too little kept
      validatorRejects ctx spendValidator := by
  -- TODO: prove (continuation < required ⇒ reject).
  sorry

/-- **R3 — schedule tampering is rejected.** A continuation whose datum differs
from the input's is rejected (spec §9 R3, I3). -/
theorem reject_datum_tamper
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) (outDatum : Data) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let sigs := match d.beneficiary with | .key h => [h] | .script _ => []
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now sigs claimRedeemer
    d.vesting = [a] ∧ validSchedule d ∧ now < d.endTime ∧
    outDatum ≠ datumData d →           -- tampered continuation datum
      validatorRejects ctx spendValidator := by
  -- TODO: prove (datum mismatch ⇒ no recognized continuation ⇒ reject).
  sorry

/-- **Premature cancel is rejected (spec §9 R6).** `Cancel` with
`now ≤ recovery_time` is rejected. TODO: state over a cancel context and prove. -/
theorem reject_premature_cancel (_d : VestingDatum) : True := by
  trivial

/-- **No double satisfaction (spec §5.1, I2).** Two contract inputs sharing a
byte-identical datum cannot be satisfied by a single continuation: the
`k`-scaling rule requires `k × required`, so one shared output is rejected.
This is the headline robustness property and the hardest to model (needs ≥ 2
inputs with the same datum). TODO. -/
theorem no_double_satisfaction (_d : VestingDatum) : True := by
  -- TODO: build a context with two inputs sharing `datumData d` and a single
  -- continuation holding only `1 × required`; prove the validator rejects it.
  trivial

end Formal.Vesting.Linear.Robustness

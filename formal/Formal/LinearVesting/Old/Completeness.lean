/-
Linear vesting — COMPLETENESS: `spec ⇒ accepts` (spec §8).

Acceptance proofs for the constructed contexts under their stated hypotheses.
These do not establish completeness for arbitrary transactions.
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.Old.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.Old.Soundness

namespace Formal.LinearVesting.Old.Completeness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (Address Redeemer)
open Formal.Shared.Common (validatorAccepts)
open Formal.LinearVesting.Old.Spec
open Formal.LinearVesting.Old.Soundness (mkClaimCtx mkClaimCtxW mkClaimCtxDouble withAsset scriptAddress)
open Formal.LinearVesting.Script (spendValidator)

/-- The compiled validator accepts the constructed single-native-asset claim
before vesting ends when the schedule is valid, the beneficiary key appears in
the signatories, and the continuation reproduces the input datum and payment
credential and holds at least the required remainder. -/
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
    a.policy ≠ "" ∧
    validSchedule d ∧
    now < d.endTime ∧
    (∃ h, d.beneficiary = .key h) ∧                          -- C1 (key case)
    outAddr.addressCredential = scriptAddress.addressCredential ∧ -- C3
    outQty ≥ required a.total d.startTime d.endTime now →     -- C4
      validatorAccepts ctx spendValidator := by
  dsimp only
  intro h
  rcases d with ⟨beneficiary, locker, vesting, startTime, endTime, recoveryTime⟩
  rcases outAddr with ⟨paymentCredential, stakingCredential⟩
  rcases h with ⟨hVesting, hPolicy, hSchedule, hTime, ⟨key, hKey⟩, hAddress, hQty⟩
  cases hVesting
  cases hKey
  cases hAddress
  blaster

/-- A specific, well-formed partial `Claim`, fully concrete:
- one asset `assetA`, total 100, schedule `[1000, 2000]`, recovery 3000;
- `now = 1500` (so vested = 50, required = 50);
- beneficiary key signed; continuation at the script address, datum reproduced,
  holding the whole 100 (at least `required`), a valid claim (here claiming nothing).

Because every field is a literal, `blaster` just evaluates the CEK machine on
concrete data, so it is fast. A green check confirms the whole pipeline: loaded
UPLC, datum/value encoding, validity range, CEK, and the acceptance predicate. -/
theorem claim_accept_concrete :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)   -- input: ada + 100 assetA
        scriptAddress                                 -- continuation at script addr
        (withAsset 2000000 "policyA" "assetA" 100)   -- keeps the bundle (≥ required)
        (datumData dConcrete)                         -- reproduces the datum
        1500                                          -- now: start < now < end
        ["beneficiary_key_hash"]                      -- beneficiary signs
        claimRedeemer)
      spendValidator := by
  blaster

/-- Complementary coverage to `claim_accept_generic_schedule` (not subsumed by
it): `now` is **unconstrained** (any time, including before `start` and after
`end`) and both ada amounts are symbolic. The continuation keeps the whole
bundle (token qty 100 = total), so the required remainder is met for any `now`
(`required ≤ total` always) and the validator ignores the surplus ada, so no
hypotheses are needed. The general theorem windows `now` and fixes ada; this one
covers the rest of the time line for the full-retention claim. -/
theorem claim_accept_anytime (now inLovelace outLovelace : Int) :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset inLovelace "policyA" "assetA" 100)
        scriptAddress
        (withAsset outLovelace "policyA" "assetA" 100)
        (datumData dConcrete)
        now
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Maximally general single-asset partial-claim completeness.** Everything is
symbolic: beneficiary key hash, asset policy/name, `total`, the full schedule
`start/finish/recovery`, `now` (in the open window `(start, finish)`), and the
claimed amount via `outQty ≥ required`. This is the consolidated completeness
result for a single-asset, key-auth claim; it subsumes the concrete-instance
rungs that led here (fixed amount/total/identities/schedule), all removed once
it closed.

`policy ≠ ""` keeps the asset distinct from the ada entry so the value lookup is
unambiguous; `bene` appears in both the datum and the signatory list, so the
auth equality holds by construction. The window `start < now < finish` keeps
both `now − start > 0` and the divisor
`finish − start > 0`, so the validator's `divideInteger` (floor) and our
`Spec.vested`'s `Int./` agree, and `vested` is in its middle branch. The new
difficulty over the `total` rung is the now-symbolic divisor `finish − start`;
the validator's remainder and `Spec.required` are the same expression, so this
closes iff `blaster` unifies the two divisions rather than reasoning about their
value. -/
theorem claim_accept_generic_schedule
    (bene policy name : ByteString)
    (total start finish recovery now outQty : Int)
    (hpol : policy ≠ "")
    (htot : 0 ≤ total)
    (hlo : start < now) (hhi : now < finish)
    (h : outQty ≥ required total start finish now) :
    validatorAccepts
      (mkClaimCtx (dSched bene policy name total start finish recovery)
        (withAsset 2000000 policy name total)
        scriptAddress
        (withAsset 2000000 policy name outQty)
        (datumData (dSched bene policy name total start finish recovery))
        now
        [bene]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Script-credential auth (accept side).** A beneficiary that is a *script*
credential `bhash` is authorized by a withdrawal keyed by that script
(withdraw-0), with no key signature. The claim is accepted. This is the other
half of the pluggable-credential design (ARCHITECTURE §3): a script can fill the
beneficiary role exactly like a key. -/
theorem claim_accept_script_auth (bhash : ByteString) :
    validatorAccepts
      (mkClaimCtxW (dScript bhash)
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData (dScript bhash))
        1500
        []                              -- no key signature
        [(.ScriptCredential bhash, 0)]  -- withdraw-0 keyed by the beneficiary script
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Batched claim accepted (spec §5.1, C4).** Two contract inputs sharing a
datum, with two separate continuations each holding the required remainder
(50 at `now = 1500`), are accepted. -/
theorem claim_accept_two_inputs :
    validatorAccepts
      (mkClaimCtxDouble dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)   -- each input holds 100
        [withAsset 2000000 "policyA" "assetA" 50,
         withAsset 2000000 "policyA" "assetA" 50]   -- each continuation holds required
        (datumData dConcrete)
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Full-claim completeness (spec §8.2 / I4).** At or after `end_time` the
required remainder is zero, so the continuation constraint is trivially met for
any non-negative `outQty` (including 0, i.e. taking the whole bundle). The claim
is accepted for any `now ≥ end_time`. -/
theorem claim_complete_full (now outQty : Int) (hge : 2000 ≤ now) (hq : 0 ≤ outQty) :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" outQty)  -- required = 0, so any ≥ 0 works
        (datumData dConcrete)
        now
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Cancel completeness (spec §8.3).** The authorized locker, at any
`now > recovery_time` (strict; here `3000 < now`), with a well-formed schedule,
can cancel. No continuation is required (the lone output is ignored on the
`Cancel` path). -/
theorem cancel_complete (now : Int) (hgt : 3000 < now) :
    validatorAccepts
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData dConcrete)
        now
        ["locker_key_hash"]            -- locker authorized
        cancelRedeemer)
      spendValidator := by
  blaster

end Formal.LinearVesting.Old.Completeness

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
import Formal.Vesting.Linear.Script
import Formal.Vesting.Linear.Soundness
import Formal.Vesting.Linear.Completeness

namespace Formal.Vesting.Linear.Robustness

open PlutusCore.UPLC.Term (Program)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open CardanoLedgerApi.V3 (Address Redeemer)
open Formal.Common (validatorRejects)
open Formal.Vesting.Linear.Spec
open Formal.Vesting.Linear.Soundness (mkClaimCtx mkClaimCtxW mkClaimCtxHashInput mkClaimCtxDouble withAsset scriptAddress)
open Formal.Vesting.Linear.Script (spendValidator)
open Formal.Vesting.Linear.Completeness (dConcrete dScript)

set_option warn.sorry false

/-- **R1 — unauthorized claim is rejected.** No signatory satisfies the
beneficiary key ⇒ the validator rejects the `Claim`. General target; the
concrete instances below are the proved ones. -/
theorem reject_unauthorized_claim
    (d : VestingDatum) (a : VestedAsset)
    (inLovelace outLovelace inQty outQty now : Int)
    (outAddr : Address) (outDatum : Data) :
    let inValue  := withAsset inLovelace a.policy a.name inQty
    let outValue := withAsset outLovelace a.policy a.name outQty
    let ctx := mkClaimCtx d inValue outAddr outValue outDatum now [] claimRedeemer
    (∃ h, d.beneficiary = .key h) →   -- key-auth instance, but NO signatories
      validatorRejects ctx spendValidator := by
  -- General version (∀ d/amounts/addr) hangs, like the completeness analogues.
  -- See the concrete instances below.
  sorry

/-- **R1, concrete: no signatory ⇒ reject.** The honest claim of
`claim_accept_concrete`, but with an EMPTY signatory list, is rejected: the
beneficiary key credential is unsatisfied, so `is_authorized` fails. -/
theorem reject_unauthorized_claim_no_sig :
    validatorRejects
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData dConcrete)
        1500
        []                           -- NO signatories
        claimRedeemer)
      spendValidator := by
  blaster

/-- **R1, concrete: wrong signer ⇒ reject.** A claim signed by some key `w`
that is **not** the beneficiary is rejected. This is the inequality form: it is
the property that makes auth meaningful, and it cannot be stated with concrete
equal hashes. `w ≠ "beneficiary_key_hash"` is the load-bearing hypothesis. -/
theorem reject_wrong_signer (w : ByteString)
    (hw : w ≠ "beneficiary_key_hash") :
    validatorRejects
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData dConcrete)
        1500
        [w]                          -- the WRONG signer
        claimRedeemer)
      spendValidator := by
  blaster

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
  -- General version; see the concrete instance below.
  sorry

/-- **R2, concrete: under-funded continuation ⇒ reject.** The honest claim, but
the continuation keeps `outQty < required` (here required = 50 at `now = 1500`).
The validator's remainder check `outQty ≥ required` fails, so the claim is
rejected (spec §9 R2, I2/B1). `outQty < required …` is the load-bearing bound. -/
theorem reject_over_release_concrete (outQty : Int)
    (hlt : outQty < required 100 1000 2000 1500) :
    validatorRejects
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" outQty)   -- keeps too little
        (datumData dConcrete)
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

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
  -- General version; see the concrete instance below.
  sorry

/-- **R3, concrete: tampered continuation datum ⇒ reject.** The honest claim of
`claim_accept_concrete`, but the continuation carries a datum `outDatum` that
differs from the input's. The validator recognizes a continuation only when its
datum is byte-identical to the input's, so the lone output is not counted, the
required remainder (50) is not preserved, and the claim is rejected (spec §9 R3,
I3). `outDatum ≠ datumData dConcrete` is the load-bearing inequality. -/
theorem reject_datum_tamper_concrete (outDatum : Data)
    (hd : outDatum ≠ datumData dConcrete) :
    validatorRejects
      (mkClaimCtx dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        outDatum                       -- TAMPERED continuation datum
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **R4 — datum-hash input is rejected (spec §3.1).** The honest claim, but the
contract input carries a datum *hash* instead of an inline datum (the resolved
datum is still supplied via the script info). The validator requires an inline
datum on its input, so the spend is rejected regardless of the (valid) hash. -/
theorem reject_datum_hash_input (datumHash : ByteString) :
    validatorRejects
      (mkClaimCtxHashInput dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)
        datumHash                      -- input datum is a HASH, not inline
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData dConcrete)
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

/-- **Script-credential auth (reject side).** A beneficiary that is a *script*
credential, with **no** withdrawal keyed by it (and no signature), is not
authorized, so the claim is rejected. The dual of `claim_accept_script_auth`:
together they show the script branch of auth is actually enforced, not merely
permitted. -/
theorem reject_script_no_withdrawal (bhash : ByteString) :
    validatorRejects
      (mkClaimCtxW (dScript bhash)
        (withAsset 2000000 "policyA" "assetA" 100)
        scriptAddress
        (withAsset 2000000 "policyA" "assetA" 100)
        (datumData (dScript bhash))
        1500
        []                              -- no signature
        []                              -- NO withdrawal
        claimRedeemer)
      spendValidator := by
  blaster

/-- **R6, concrete: premature cancel ⇒ reject.** A `Cancel` by the (authorized)
locker at any `now ≤ recovery_time` (3000) is rejected: the validator requires
the validity range to be *strictly* after `recovery_time`, so a too-early cancel
fails (spec §9 R6, §4.3). The locker is signed and the schedule is well-formed,
so timing is the only reason for rejection. `now ≤ 3000` is load-bearing.

(The single continuation output built by `mkClaimCtx` is ignored on the `Cancel`
path, which reads no outputs.) -/
theorem reject_premature_cancel (now : Int) (hle : now ≤ 3000) :
    validatorRejects
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

/-- **No double satisfaction (spec §5.1, I2).** Two contract inputs sharing a
byte-identical datum, with a single continuation holding only `1 × required`
(50 at `now = 1500`), is rejected: invoked for the first input, the validator
computes `k = 2` and requires `2 × required` (100), which the lone 50-output
fails to meet. So one shared continuation cannot satisfy two inputs; an attacker
cannot pocket the duplicate. Contrast `claim_accept_two_inputs`, where the same
two inputs with a `2 × required` continuation are accepted. -/
theorem no_double_satisfaction :
    validatorRejects
      (mkClaimCtxDouble dConcrete
        (withAsset 2000000 "policyA" "assetA" 100)   -- each input holds 100
        (withAsset 2000000 "policyA" "assetA" 50)    -- ONE continuation: only 1 × required
        (datumData dConcrete)
        1500
        ["beneficiary_key_hash"]
        claimRedeemer)
      spendValidator := by
  blaster

end Formal.Vesting.Linear.Robustness

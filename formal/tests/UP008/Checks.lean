import Blaster
import tests.UP008.Artifacts

set_option Elab.async false

namespace Tests.UP008

#eval checkArtifacts

/-- Expected Falsified: the existing vesting Claim admits the fixed junk mutation. -/
theorem vesting_claim : Formal.Vesting.Linear.Blueprint.junkToken_claim := by blaster

/-- Expected Valid: Claim falsification has an applicable baseline and mutation. -/
theorem vesting_claim_applies : Formal.Vesting.Linear.Blueprint.junkToken_claim_applies := by blaster

/-- Expected Valid, with no applicable Cancel coverage; see the next check. -/
theorem vesting_cancel : Formal.Vesting.Linear.Blueprint.junkToken_cancel := by blaster

/-- Expected Falsified: Cancel has no continuation and cannot satisfy reliance. -/
theorem vesting_cancel_applies : Formal.Vesting.Linear.Blueprint.junkToken_cancel_applies := by blaster

/-- Expected Valid: the enforcing program rejects this precise junk asset. -/
theorem enforcing_claim : Enforcing.junkToken_claim := by blaster

/-- Expected Valid: rejection is exercised on a valid mutation of an accepted baseline. -/
theorem enforcing_claim_applies : Enforcing.junkToken_claim_applies := by blaster

#print axioms vesting_claim_applies
#print axioms vesting_cancel
#print axioms enforcing_claim
#print axioms enforcing_claim_applies

end Tests.UP008

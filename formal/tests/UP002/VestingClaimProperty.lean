import Universal.Demo.Linear_vesting.NoSignatureClaim

set_option Elab.async false

namespace Universal.Demo.Linear_vesting

theorem no_signature_claim_verified : up002_Claim := by
  blaster (timeout: 600)

#print axioms no_signature_claim_verified

end Universal.Demo.Linear_vesting

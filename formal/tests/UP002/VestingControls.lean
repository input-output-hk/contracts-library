import Universal.NoSignature.Witnesses

set_option Elab.async false

namespace Universal.Demo.Linear_vesting

theorem unsigned_claim_model_applies :
    unsignedWitness.sig1 = false ∧ unsignedWitness.sig2 = false ∧
    unsignedWitness.out1Foreign = false ∧
    valid (ctx unsignedWitness (redeemerClaim unsignedWitness)) ∧
    ledgerFloor unsignedWitness ∧ realistic unsignedWitness := by
  blaster (timeout: 600)

theorem unsigned_cancel_model_applies :
    unsignedWitness.sig1 = false ∧ unsignedWitness.sig2 = false ∧
    unsignedWitness.out1Foreign = false ∧
    valid (ctx unsignedWitness (redeemerCancel unsignedWitness)) ∧
    ledgerFloor unsignedWitness ∧ realistic unsignedWitness := by
  blaster (timeout: 600)

theorem signed_claim_control_accepts :
    valid (ctx signedWitness (redeemerClaim signedWitness)) ∧
    ledgerFloor signedWitness ∧ realistic signedWitness ∧
    accepts (ctx signedWitness (redeemerClaim signedWitness)) := by
  blaster (timeout: 600)

theorem signed_cancel_control_accepts :
    valid (ctx signedWitness (redeemerCancel signedWitness)) ∧
    ledgerFloor signedWitness ∧ realistic signedWitness ∧
    accepts (ctx signedWitness (redeemerCancel signedWitness)) := by
  blaster (timeout: 600)

#print axioms unsigned_claim_model_applies
#print axioms unsigned_cancel_model_applies
#print axioms signed_claim_control_accepts
#print axioms signed_cancel_control_accepts

end Universal.Demo.Linear_vesting

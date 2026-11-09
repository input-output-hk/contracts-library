import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.NoSignature.Witnesses

set_option Elab.async false

namespace tests.UP002.Prototype.Demo.Vault

/-- The full unsigned antecedent has a concrete, nondust model witness. -/
theorem unsigned_model_applies :
    unsignedWitness.sig1 = false ∧ unsignedWitness.sig2 = false ∧
    unsignedWitness.out1Foreign = false ∧
    valid (ctx unsignedWitness (redeemer unsignedWitness)) ∧
    ledgerFloor unsignedWitness ∧ realistic unsignedWitness := by
  blaster (timeout: 600)

/-- The good validator accepts the same transaction when the owner signs. -/
theorem signed_control_accepts :
    valid (ctx signedWitness (redeemer signedWitness)) ∧
    ledgerFloor signedWitness ∧ realistic signedWitness ∧
    accepts (ctx signedWitness (redeemer signedWitness)) := by
  blaster (timeout: 600)

/-- The concrete unsigned good-vault transaction does not accept within the bound. -/
theorem unsigned_control_does_not_accept :
    rejects (ctx unsignedWitness (redeemer unsignedWitness)) := by
  blaster (timeout: 600)

#print axioms unsigned_model_applies
#print axioms signed_control_accepts
#print axioms unsigned_control_does_not_accept

end tests.UP002.Prototype.Demo.Vault

namespace tests.UP002.Prototype.Demo.Vault_buggy

/-- An explicit unsigned transaction satisfies every primary guard and is accepted. -/
theorem unsigned_counterexample_accepts :
    unsignedWitness.sig1 = false ∧ unsignedWitness.sig2 = false ∧
    unsignedWitness.out1Foreign = false ∧
    valid (ctx unsignedWitness (redeemer unsignedWitness)) ∧
    ledgerFloor unsignedWitness ∧ realistic unsignedWitness ∧
    accepts (ctx unsignedWitness (redeemer unsignedWitness)) := by
  blaster (timeout: 600)

#print axioms unsigned_counterexample_accepts

end tests.UP002.Prototype.Demo.Vault_buggy

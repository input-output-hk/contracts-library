import tests.UP002.Prototype.Demo.Vault.NoSignatureSpend

set_option Elab.async false

namespace tests.UP002.Prototype.Demo.Vault

theorem no_signature_spend_verified : up002_spend := by
  blaster (timeout: 600)

#print axioms no_signature_spend_verified

end tests.UP002.Prototype.Demo.Vault

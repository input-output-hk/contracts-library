import Universal.Demo.Vault.NoSignatureSpend

set_option Elab.async false

namespace Universal.Demo.Vault

theorem no_signature_spend_verified : up002_spend := by
  blaster (timeout: 600)

#print axioms no_signature_spend_verified

end Universal.Demo.Vault

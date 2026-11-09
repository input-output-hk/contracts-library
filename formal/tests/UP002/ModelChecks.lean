import tests.UP002.Prototype.NoSignature.Witnesses

set_option Elab.async false

#guard tests.UP002.Prototype.Demo.Vault.own.length = 28
#guard tests.UP002.Prototype.Demo.Vault_buggy.own.length = 28
#guard tests.UP002.Prototype.Demo.Linear_vesting.own.length = 28

#guard tests.UP002.Prototype.Demo.Vault.unsignedWitness.sig1 = false
#guard tests.UP002.Prototype.Demo.Vault.unsignedWitness.sig2 = false
#guard tests.UP002.Prototype.Demo.Vault_buggy.unsignedWitness.sig1 = false
#guard tests.UP002.Prototype.Demo.Vault_buggy.unsignedWitness.sig2 = false
#guard tests.UP002.Prototype.Demo.Linear_vesting.unsignedWitness.sig1 = false
#guard tests.UP002.Prototype.Demo.Linear_vesting.unsignedWitness.sig2 = false

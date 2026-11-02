import Universal.NoSignature.Witnesses

set_option Elab.async false

#guard Universal.Demo.Vault.own.length = 28
#guard Universal.Demo.Vault_buggy.own.length = 28
#guard Universal.Demo.Linear_vesting.own.length = 28

#guard Universal.Demo.Vault.unsignedWitness.sig1 = false
#guard Universal.Demo.Vault.unsignedWitness.sig2 = false
#guard Universal.Demo.Vault_buggy.unsignedWitness.sig1 = false
#guard Universal.Demo.Vault_buggy.unsignedWitness.sig2 = false
#guard Universal.Demo.Linear_vesting.unsignedWitness.sig1 = false
#guard Universal.Demo.Linear_vesting.unsignedWitness.sig2 = false

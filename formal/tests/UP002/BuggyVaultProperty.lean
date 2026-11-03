import Universal.Demo.Vault_buggy.NoSignatureSpend

set_option Elab.async false
set_option warningAsError true

namespace Universal.Demo.Vault_buggy

-- Expected falsification is a successful negative control, not an admitted theorem.
#blaster (solve-result: 1) (timeout: 600) [up002_spend]

end Universal.Demo.Vault_buggy

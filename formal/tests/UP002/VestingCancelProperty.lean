import Universal.Demo.Linear_vesting.NoSignatureCancel

set_option Elab.async false

namespace Universal.Demo.Linear_vesting

theorem no_signature_cancel_verified : up002_Cancel := by
  blaster (timeout: 600)

#print axioms no_signature_cancel_verified

end Universal.Demo.Linear_vesting

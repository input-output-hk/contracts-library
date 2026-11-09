import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.Demo.Linear_vesting.NoSignatureCancel

set_option Elab.async false

namespace tests.UP002.Prototype.Demo.Linear_vesting

theorem no_signature_cancel_verified : up002_Cancel := by
  blaster (timeout: 600)

#print axioms no_signature_cancel_verified

end tests.UP002.Prototype.Demo.Linear_vesting

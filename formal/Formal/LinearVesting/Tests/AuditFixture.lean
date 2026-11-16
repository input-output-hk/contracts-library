namespace Formal.LinearVesting.Tests.AuditFixture

def supportValue : Nat := 1

theorem identity (n : Nat) : n = n := rfl

theorem dependent (n : Nat) : n = n := identity n

end Formal.LinearVesting.Tests.AuditFixture

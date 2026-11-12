namespace Formal.Vesting.Linear.Tests.AuditFixture

def supportValue : Nat := 1

theorem identity (n : Nat) : n = n := rfl

theorem dependent (n : Nat) : n = n := identity n

end Formal.Vesting.Linear.Tests.AuditFixture

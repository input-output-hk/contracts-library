import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.Demo.Vault.NoSignatureSpend
import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.Demo.Vault_buggy.NoSignatureSpend
import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.Demo.Linear_vesting.NoSignatureClaim
import Formal.Properties.Universal.UP002.Tests.Standalone.Prototype.Demo.Linear_vesting.NoSignatureCancel

/-!
Concrete controls for Jonathan's historical UP-002 models. These values do not
restrict the universally quantified Holes domains in the primary propositions.
-/

namespace tests.UP002.Prototype.Demo.Vault

def unsignedWitness : Holes :=
  { in2 := false, out2 := false, out1Script := false, out1Foreign := false
    sig1 := false, sig2 := false, mint1 := false, lowFin := false
    d_owner1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    o_owner2 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    r_any3 := 0
    s1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", s2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    payee := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", payee2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    policy := "cccccccccccccccccccccccccccc", name := "asset"
    inLov := 3000000, inLov2 := 2000000, outLov := 2000000, outLov2 := 2000000
    qty := 0, lo := 0, fee := 1000000 }

def signedWitness : Holes := { unsignedWitness with sig1 := true }

end tests.UP002.Prototype.Demo.Vault

namespace tests.UP002.Prototype.Demo.Vault_buggy

def unsignedWitness : Holes :=
  { in2 := false, out2 := false, out1Script := false, out1Foreign := false
    sig1 := false, sig2 := false, mint1 := false, lowFin := false
    d_owner1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    o_owner2 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    r_any3 := 0
    s1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", s2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    payee := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", payee2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    policy := "cccccccccccccccccccccccccccc", name := "asset"
    inLov := 3000000, inLov2 := 2000000, outLov := 2000000, outLov2 := 2000000
    qty := 0, lo := 0, fee := 1000000 }

end tests.UP002.Prototype.Demo.Vault_buggy

namespace tests.UP002.Prototype.Demo.Linear_vesting

/-- The modeled asset is fully vested at the finite lower bound. -/
def unsignedWitness : Holes :=
  { in2 := false, out2 := false, out1Script := false, out1Foreign := false
    sig1 := false, sig2 := false, mint1 := false, lowFin := true
    d_benefici1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", d_locker2 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    d_policy3 := "", d_name4 := "", d_total5 := 2000000
    d_start_ti6 := 0, d_end_time7 := 10, d_recovery8 := 20
    o_benefici9 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", o_locker10 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    o_policy11 := "", o_name12 := "", o_total13 := 2000000
    o_start_ti14 := 0, o_end_time15 := 10, o_recovery16 := 20
    s1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", s2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    payee := "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", payee2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    policy := "cccccccccccccccccccccccccccc", name := "asset"
    inLov := 3000000, inLov2 := 2000000, outLov := 2000000, outLov2 := 2000000
    qty := 0, lo := 30, fee := 1000000 }

def signedWitness : Holes := { unsignedWitness with sig1 := true }

end tests.UP002.Prototype.Demo.Linear_vesting

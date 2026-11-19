import PlutusCore.UPLC

namespace Formal.LinearVesting.Old.Script

open PlutusCore.UPLC.Term (Program)

#import_uplc linearVestingSpendScript PlutusV3 flat_hex "./Scripts/linear_vesting_old_spend.flat"

/-- The compiled vesting validator used by the archived proofs. -/
def spendValidator : Program := linearVestingSpendScript.script

end Formal.LinearVesting.Old.Script

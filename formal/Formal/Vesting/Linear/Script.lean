/-
Linear vesting — the compiled validator, loaded once and shared.

`#import_uplc` reads the flat produced by `just flats` (gitignored). Keeping it
in its own module lets both Soundness and Completeness state theorems against
the *same concrete* `spendValidator`. Proving `blaster` goals requires a
concrete program — an abstract `validator : Program` gives the SMT backend
nothing to execute and makes proofs hang.
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3

namespace Formal.Vesting.Linear.Script

open PlutusCore.UPLC.Term (Program)
open CardanoLedgerApi.V3 (spendingInputs)

#import_uplc linearVestingSpendScript PlutusV3 single_cbor_hex "Formal/Vesting/Linear/linear_vesting_spend.flat"

#prep_uplc appliedLinearVesting linearVestingSpendScript spendingInputs 1000

#print appliedLinearVesting.prop

/-- The compiled `spend` handler of `validators/linear_vesting.ak`. -/
def spendValidator : Program := linearVestingSpendScript.script

end Formal.Vesting.Linear.Script

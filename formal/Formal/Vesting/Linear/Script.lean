/-
Linear vesting — the compiled validator, loaded once and shared.

`#import_blueprints` reads the CIP-57 blueprint `../onchain/plutus.json`
(produced by `aiken build`). Keeping it in its own module lets both Soundness
and Completeness state theorems against the *same concrete* `spendValidator`.
Proving `blaster` goals requires a concrete program — an abstract
`validator : Program` gives the SMT backend nothing to execute and makes proofs
hang.
-/
import PlutusCore.UPLC

namespace Formal.Vesting.Linear.Script

open PlutusCore.UPLC.Term (Program)

#import_blueprints LinearVesting "../onchain/plutus.json"

/-- The compiled `spend` handler of `validators/linear_vesting.ak`. -/
def spendValidator : Program := LinearVesting.linear_vesting_linear_vesting_spend.script

end Formal.Vesting.Linear.Script

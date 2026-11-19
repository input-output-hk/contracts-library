/-
This module imports the linear-vesting model, its completeness, soundness,
and robustness theorems, and the bounded Claim and Cancel agreement proofs
with their corollaries. Both suites use the same compiled spending validator.

See `docs/vesting/spec.md`.
-/
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.TxBuilder
import Formal.LinearVesting.CancelSound
import Formal.LinearVesting.CancelComplete
import Formal.LinearVesting.ClaimSound
import Formal.LinearVesting.ClaimComplete
import Formal.LinearVesting.Robustness
import Formal.LinearVesting.Functionality
import Formal.LinearVesting.MultiTx
import Formal.LinearVesting.Corollaries
import Formal.LinearVesting.Tests

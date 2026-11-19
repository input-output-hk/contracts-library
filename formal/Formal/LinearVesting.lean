/-
This module imports the linear-vesting model, its completeness, soundness,
and robustness theorems, and the bounded Claim and Cancel agreement proofs
with their corollaries. Both suites use the same compiled spending validator.

See `docs/vesting/spec.md`.
-/
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.Completeness
import Formal.LinearVesting.Soundness
import Formal.LinearVesting.Robustness
import Formal.LinearVesting.SpecNew
import Formal.LinearVesting.Cancel
import Formal.LinearVesting.Claim
import Formal.LinearVesting.Corollaries

/-
This module imports the active linear-vesting model, the bounded Claim and
Cancel agreement proofs for the current spending validator, and their
corollaries and tests.

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

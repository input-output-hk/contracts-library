/-
Linear vesting — aggregator. Importing this pulls the whole proof set for the
`vesting/linear` contract: the pure spec model and the three property layers
(Completeness §8, Soundness §9, Robustness §9/§5.1).

See `docs/vesting/spec.md`.
-/
import Formal.LinearVesting.Spec
import Formal.LinearVesting.Script
import Formal.LinearVesting.Completeness
import Formal.LinearVesting.Soundness
import Formal.LinearVesting.Robustness

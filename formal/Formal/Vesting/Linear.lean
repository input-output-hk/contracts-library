/-
Linear vesting — aggregator. Importing this pulls the whole proof set for the
`vesting/linear` contract: the pure spec model and the three property layers
(Completeness §8, Soundness §9, Robustness §9/§5.1).

See `specs/vesting/linear-vesting.md`.
-/
import Formal.Vesting.Linear.Spec
import Formal.Vesting.Linear.Script
import Formal.Vesting.Linear.Completeness
import Formal.Vesting.Linear.Soundness
import Formal.Vesting.Linear.Robustness

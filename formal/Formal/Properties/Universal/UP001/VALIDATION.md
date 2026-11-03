# UP-001 run migration validation

The property body and six original model bodies match `0e176dd` byte for byte.
The new runtime exports supply each model's context builder, admission policy,
and fixed purpose. The public command uses `Run.lean` for all three properties.

| Check | Observed result |
| --- | --- |
| Six goals compared with the earlier generator | Same families, names, expectations, and 5,000,000-step bound |
| Model list, declared-purpose filtering, and invalid configuration | Unit checks passed |
| Normal and deliberately buggy vaults | Five `PASS` and five expected `FAIL`; declared spending skipped |
| Always-rejecting fixture with only a fallback handler | All six purpose goals `PASS` |
| Fixture declaring all six purposes | Six `SKIPPED`; no proof observations or execution manifests |
| UP-012 and UP-015 on the vesting fixture | Three `PASS`, one incompatible model `SKIPPED` |
| Full workflow aggregate | All 25 registered suites passed |

The four targeted public-command methods passed. Proof runs used 300,000 ms per
combination. UP-001 retains 5,000,000 CEK steps; UP-012 and UP-015 retain 1,000,000.
These checks preserve the existing model domains and SMT trust boundary.

The discovery and UP-001 unit fixtures also allow additional properties and
models without extending their fixed comparison inventories. Both unit suites
passed again after that test-only refinement.

Local evidence stays ignored under `output/up001-migration-validation/` and
`output/public-cli.cgtk2k0v/`. The older `universal` adapters remain for comparison.

# Shared-support relocation validation

The relocation was validated at `40fadca9c8dc8432246970df5c3ed6c89de3210f`,
based on foundation `7d30a34a28e69dcf89de182d4336a8a4d3b79829`.
The four helper modules retain their definition bodies after the planned
module/path and declaration-namespace substitutions. A comparison of 67 affected
code, generated-template, and metadata files found only those substitutions and
one explanatory comment correction.

| Check | Result |
| --- | --- |
| Helpers, app, test targets, and affected definition-only modules | Build passed |
| Existing blueprint-generator tests | 47 passed |
| Structural return-datum checks | Passed |
| Generator, metadata, and property/model parity suites | Passed |
| Full `./plutus-upv test` | 25/25 suites passed; outer command 854.676 seconds |
| Public vesting UP-012/UP-015 run | 3 PASS, 1 unsupported SKIPPED, no errors/timeouts |
| Recorded source hashes | All 524 matched after validation |

The public run's six obligations were Valid. Validation inspected the individual
check results, exact reviewed pairing limitations, nine generated Lean modules,
and shared source index. Generated imports and retained execution helpers use
`Formal.Support`; no old helper namespace appeared in those generated modules.
The public command completed in 161.359 seconds, including startup.

Reproduce the main checks from `formal/`:

```sh
python3 -B -m unittest discover -s tests -p test_process_blueprint.py
lake env lean tests/ReturnDatum.lean
./plutus-upv test
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --validator linear_vesting.linear_vesting --check UP-012 --check UP-015 --timeout-ms 300000
```

The Python command checks the separate retained blueprint translator; the product
runtime remains Lean. Tool versions were Lean 4.24.0 and Z3 4.15.2, with unchanged
root lockfile revisions: ledger `7b743af`, PlutusCore `4ef4860`, and Blaster `402f6d2`.
Focused Astra review found no remaining issue after documentation corrections.
Raw logs, receipts, and source hashes remain in local ignored evidence folders.

The current property formulas, native models, bounds, and artifact identities
retain their meanings. Held UP-009/UP-016 proof files received naming updates but
were not executed. Existing CEK admissions and Blaster's SMT trust boundary remain;
these results do not establish general validator or deployed-ledger safety.

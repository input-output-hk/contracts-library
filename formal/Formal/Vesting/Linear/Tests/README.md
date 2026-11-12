# Linear vesting M1.2 suite

This suite checks the linear-vesting specification proof modules together.
It belongs to the validator milestone, separately from reusable UP-* property
checks and the Plutus UPV workflow tests.

From `formal/`, inspect the suite or run it:

```sh
lake exe test_m12 --list
lake exe test_m12
```

The suite visits `Spec`, `Script`, `Soundness`, `Completeness`, and `Robustness`.
Each module has a shared build-and-audit deadline of **300,000 ms** by default.
Use `--timeout-ms N` to change that per-module deadline. It is not the validator's
CEK execution bound and does not change any theorem statement or model.

Prepare the artifact `Scripts/linear_vesting_spend.flat` before running the
validator-dependent steps; see the [specification-proof pipeline](../../../../README.md#specification-proof-pipeline).
The suite does not generate or replace it. If it is missing, `Script` and its
dependent modules report `BLOCKED`; the independent `Spec` step can still run.

## What the result means

Lake builds each requested module using its normal dependency tracking. The
suite then runs a fresh audit of that module's theorem axioms. Unchanged compiled
proof modules can be reused; this command does not force a fresh solver run for
every theorem. The Script audit also checks that the current flat artifact
matches the validator loaded by `Script.spendValidator`.

| Status | Meaning |
| --- | --- |
| `PASS` | The proof module built and its theorem audit found only the recognized axioms |
| `BUILT` | The supporting Script module built and matched the current artifact |
| `PENDING` | The audit found a theorem depending on `sorryAx`; its proof remains unfinished |
| `BLOCKED` | A prerequisite artifact or module was unavailable |
| `TIMEOUT` | The module's build-and-audit budget expired |
| `ERROR` | Build, audit, unrecognized-axiom, or retained-evidence processing failed |
| `NOT RUN` | The step has no completed attempt yet |

The command exits `0` only when every step is `PASS` or `BUILT`; other completed
runs exit `2`. A successful build alone does not discharge a documented `sorry`
target. Successful Blaster theorems retain the SMT-backed `blasterProven` trust
boundary. Existing [coverage and open targets](../README.md) still determine the
milestone's scope.

## Retained output

Each run prints progress and command logs and creates a fresh ignored directory
under `formal/output/m12.XXXXXXXX/`. It retains:

- `summary.txt` and `summary.json`, including incomplete outcomes.
- `artifact.json` and copies of the toolchain, Lake manifest, and Lake configuration.
- A directory per attempted module, containing build logs, the generated axiom
  audit, audit logs, and structured observations.

These files record the run performed. They do not claim that historical standalone
candidate proofs ran again or that all validator inputs are covered.

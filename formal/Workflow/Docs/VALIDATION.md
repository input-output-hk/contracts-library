# Validation history

The checkpoints below preserve their original claims, bounds, and measurements.
They refer to the code layouts and capabilities at those revisions. Consult the
[overview](../README.md) and [user guide](USER-GUIDE.md) for current operation.
Local test outputs are evidence of their recorded runs, not performance guarantees.

## Generated comments and independent unit checks

Generated headers now identify their current Lean emitters while retaining the
original PR/SHA provenance. The UP-012 transaction-model instructions direct
edits to the profile source followed by another run. Only line comments changed
in generated Lean; all definitions, propositions, bounds, and artifact guards
remain identical to the pre-cleanup sources after removing those comments.

`workflow_generator_tests` now runs only generic Generator unit checks. The
scenario contract checks remain in each complete workflow suite. This cleanup
removes the extra aggregator. The independent unit command, both scenario contract
checks, and scoped builds pass. Generated support modules and all nine proposition
definitions type-check without invoking the solver. Full solver-suite evidence
remains that of the preceding structural checkpoint.

## Core and test separation

The structural refactor preserves twelve fixed input/oracle payloads byte-for-byte
and moves test code under `Workflow/Tests/`. Candidate definitions live under
`Candidates/`; the UP-012 model and pinned artifact guard belong to its scenario.
The core components and generic orchestration have no imports from candidate
definitions, test code, or the project's property models.

A clean project build, reusing only copied pinned dependency caches, built
`Workflow` and `Workflow.Main` without producing candidate, test, or project-model
modules. The subsequent CLI/test build prepared its own model dependencies and
passed support/proposition type-checking. No old project build artifacts were
copied into that validation workspace.

All component checks and real Valid/Falsified controls passed after the moves.
The UP001 workflow suite retained PASS/0, FAIL/1, input-error/2, and timeout/2.
The UP012 suite retained four `PASS` observations and unsupported-profile/2.
For both passing scenarios, every generated Lean source file matched the saved
pre-refactor baseline byte-for-byte. Propositions, bounds, expected results,
selection defaults, and local output behavior remain unchanged. Applicability
relationships and additional CLI selection modes remain separate design work.

## Experimental UP-012 vesting suite

The existing suite from PR #55 at `f5cbda7df624f2496dd2e6fe354a0cd15365b923`
completed all four jobs through the CLI: two signer-removal statements and two
applicability statements. All observations were Valid; Reporter emitted four
`PASS` rows and exit code zero. Execution took 64,283 ms under a 300,000 ms shared
budget: Types 1,799 ms, Tx 1,395 ms, and Checks 61,084 ms.

All three generated source files match the pinned candidate after only module
namespace/import replacement and embedding the supplied compiled script. The
propositions, typed data, transaction shapes, and 1,000,000-step bound remain
unchanged. The profile accepts only the original unparameterized vesting artifact.
Both supplied shapes have one signatory; the operation removes the first key.
General required-signer semantics remain a candidate-design question.

Generator fixture checks passed for the four propositions, provider selection,
unchanged UP-001 default, and explicit rejection of unsupported profiles.
Executor fixture checks also pass. These bounded observations retain Blaster's
SMT verification trust boundary and the original suite's model limits.

## Persistent output folders

The CLI now writes each run to its own `formal/output/run.XXXXXXXX/` directory.
The passing vault, failing vault, invalid-code, and timeout scenarios all retained
their expected 0/1/2 exit codes in separate output folders. Reports exist for all
four cases; executed plans also retain generated sources, logs, and `execution.json`.
Recorded module paths point into the actual output directory, and earlier runs
remain intact. Executor fixture checks also cover parent paths containing spaces,
distinct runs, retained source files, and a parent path that is a file.

## CLI delivery checks

The [quickstart](USER-GUIDE.md) uses the compiled vault fixtures from PR #47 at
`0dde8ae76e3f8a239bf06685f72327aed4a7c3ef`, with their source and dependency
metadata now preserved under `Workflow/Tests/UP001/Inputs/`. The blueprint SHA-256 is
`afd375487a56be74f83f60e7c94fc2008f6e79b418a7bde3f1575bb4c6c9b426`.

The existing `lake exe universal` command produced these outcomes on the
prepared Linux toolchain:

| Scenario | Observed report | Exit code |
| --- | --- | --- |
| `vault.vault`, 120-second budget | Five `PASS` rows, each observed Valid | 0 |
| `vault_buggy.vault_buggy`, 120-second budget | Five `FAIL` rows, each observed Falsified | 1 |
| Invalid hexadecimal compiled code | `INCONCLUSIVE` before execution | 2 |
| `vault.vault`, one-millisecond budget | Five `INCONCLUSIVE` rows, execution budget exhausted | 2 |

The negative demo initially exposed a diagnostic-format bug: Blaster emits
counterexample fields with a leading space before `-`, which Executor treated
as unrelated errors. Commit `d582c8a` accepts that indentation while retaining
file, declaration, and source-position matching. The repeated negative run
returned the expected FAIL report. Regression checks cover indented values,
wrong positions, and values without a Falsified marker. Real arithmetic controls
now include a quantified counterexample; Executor and Reporter integrations pass.

These runs used Lean 4.24.0, Z3 4.15.2, the pinned dependencies, and the existing
5,000,000-step UP-001 scope. They used the installed tools directly in the prepared
checkout. This checkpoint did not rebuild the Aiken fixtures or validate installation
on a fresh machine. Raw reports, inputs, sources, and logs remain separate evidence
from the fixture source descriptions.

## Reviewed 5,000,000-step checkpoint

The owner approved a UP-001-only bound change after semantic review and five
individual experiments. The provider emits literal `5000000` while retaining
the raw redeemer domain, full per-purpose context, and negated-acceptance
predicate. The shared `ledgerFuel` helper remains 1,000,000 for other candidates.

The provider source SHA-256 for this checkpoint is
`c3a327075021bc07fbdec68a7f830f4adfe28b9f699f6247314219a4d79d398d`.
The compiled vesting artifact, toolchain, and dependency pins match the original
snapshot below.

### Individual proof experiments

Each purpose used a fresh workspace, one proof-compilation attempt, and a
120-second limit. Support compilation ran separately.

| Purpose | Result | Proof compilation |
| --- | --- | --- |
| Mint | Valid, exit 0 | 10.48 s |
| Withdraw | Valid, exit 0 | 11.32 s |
| Publish | Valid, exit 0 | 41.55 s |
| Vote | Valid, exit 0 | 13.80 s |
| Propose | Valid, exit 0 | 9.74 s |

The updated declaration fixture exactly matches these five experimental
statements. Scoped builds, Generator fixtures, and Input-to-Generator integration
on both the fixture and vesting blueprint passed. The integration harness only
type-checks propositions; it does not run solver proofs.

These observations retain the bounded non-acceptance meaning and Blaster's SMT
trust boundary. Fuel exhaustion satisfies the claim. Individual timings do not
establish a combined workflow time or a performance benchmark.

### Complete workflow at the reviewed bound

From `formal/`, with the pinned dependencies and tools prepared:

```sh
lake exe universal ../onchain/plutus.json linear_vesting.linear_vesting --check UP-001 --timeout-ms 120000
```

The updated workflow completed all five checks in **71,712 ms** under the
120,000 ms shared execution budget. Support compilation took 1,432 ms and the
Checks module took 70,277 ms. Reporter emitted five PASS rows and exit code zero.
All five observed results were Valid, and both execution metadata and report
rows recorded the 5,000,000-step scope. The generated declarations matched the
reviewed fixture; the source artifact and shared helpers remained unchanged.

This complete run is separate evidence from the individual experiments above.
It is one timing observation, without a performance guarantee or a claim that
the larger bound improves runtime. The default shared execution budget remains
30,000 ms; the example explicitly supplies 120,000 ms.

## Original 1,000,000-step baseline

The four-component prototype completed all five unparameterized UP-001
obligations for the linear-vesting blueprint in 82.1 seconds with a 120-second
shared execution budget. Reporter emitted five PASS rows and exit code zero.
No code, check statement, or CEK bound changed during this validation.

### Snapshot and scope

| Item | Value |
| --- | --- |
| Implementation | `d3bce414a3417b9227fa92f1e0a33672d2829749` |
| Candidate reference | `b44b6b0757a75d79b79a4de4712523ee3978760e` |
| Target | `linear_vesting.linear_vesting`, without parameters |
| Blueprint SHA-256 | `3d574b4f9c9e1d9998f96dd5ad27e000b2e2f244e8170f77af2bf02dcfdd8b0d` |
| Compiled-code SHA-256 | `29a7b3efd7c2064887a178696cf4ca76ad3ec63d66ca4ac848acae539638fd70` |
| Compiler recorded in blueprint | Aiken `v1.1.22+39d6b04` |
| Toolchain | Lean 4.24.0, Z3 4.15.2, and the pinned dependencies |
| Claim | No acceptance within `ledgerFuel` for each undeclared purpose |
| Bound | 1,000,000 CEK steps; fuel exhaustion satisfies the claim |

The artifact was an existing compiled snapshot, not a fresh Aiken rebuild.
Each result records Blaster's `blasterProven` warning: SMT verification without
a reconstructed proof term. The results support these compiled-model claims,
not general validator safety, source correspondence, or deployment assurance.

### Controlled single-obligation comparison

Both paths used the same mint-purpose theorem declaration, namespace, compiled
script, helper source, lockfile, and tools. Support modules compiled before
each fresh proof compilation, which had a 30-second limit.

| Path | Support compilation | Mint-purpose proof compilation | Result |
| --- | --- | --- | --- |
| Original candidate | 1.96 s | 9.09 s | Valid, exit 0 |
| Modular generator | 1.72 s | 9.20 s | Valid, exit 0 |

The observed timings are close. This single comparison gives no evidence of a
substantial single-obligation slowdown; it is not a performance benchmark.

### Complete workflow at the original revision

At implementation revision `d3bce414a3417b9227fa92f1e0a33672d2829749`, from
`formal/` with the pinned dependencies and tools prepared:

```sh
lake exe universal ../onchain/plutus.json linear_vesting.linear_vesting --check UP-001 --timeout-ms 120000
```

The recorded execution used 82,093 ms: 1,794 ms for support compilation and
80,295 ms for the five-obligation Checks module. All five observations were
Valid and matched their declared expectations.

Earlier 5- and 10-second executions remained inconclusive. A preliminary
30-second Checks-module probe also timed out. Those short budgets could not
complete this measured workload. The default remains 30,000 ms; use an explicit
larger budget for this example. One successful run does not guarantee its
runtime on another machine or run.

At this original checkpoint, the component fixtures, real Valid/Falsified
arithmetic controls, and all 54 legacy Python tests also passed. Those results
remain distinct from the vesting claim above. Each new execution retains its
own report, input snapshot, generated sources, raw logs, and `execution.json`
for review.

## Plutus UPV CLI and aggregate tests

The branded `plutus-upv run` entry point preserves the existing provider
statements, bounds, and result rules. `plutus-upv test` builds explicit workflow
targets and runs all ten registered suites with verbose output and saved logs.
The legacy `universal` entry point remains available.

From the repository root, `./formal/plutus-upv test` completed with exit zero:
all ten suites passed in 343,659 ms, including the build. Coverage includes four
component unit suites, test-runner controls, three component integration suites,
and both UP001/UP012 scenarios. The runner controls verify build failure blocks
stale executables, later suites run after a failure, expected negative text does
not fail a suite, stdout/stderr remain available, and output reaches its log
before the child exits. The live-output control also preserves UTF-8 text.

Launcher checks covered help, invalid usage, relative blueprint paths, spaces,
missing inputs, and legacy help. The candidate definitions, UP012 profile,
Input, Executor, and Reporter outcome logic were unchanged. Documentation and
shell syntax checks passed. Test output stays under ignored `formal/output/`;
the measured suite run retained `test.OaDTtfhF/summary.json` and per-suite logs.

## Applicability qualification and partial results

The reporting checkpoint adds explicit job roles and applicability references,
completed-evidence markers, scoped qualification, and qualified FAIL precedence.
Raw observations remain visible when applicability is false or unavailable.

`./formal/plutus-upv test` passed all ten suites in 330,971 ms including build.
Controlled tests cover false, unknown, missing, duplicated, and invalid support;
separate action links; metadata corruption; completed observations beside later
timeouts; and mixed FAIL/INCONCLUSIVE aggregation. A real Lean/Blaster arithmetic
control retained raw Valid and Falsified while reporting both rows INCONCLUSIVE
because the applicability obligation was false.

The full UP001 and UP012 scenarios retained their expected outcomes, including
the signer-identity negative control. The emitted Types/Checks for UP001 and
Types/Tx/Checks for UP012 matched the previous CLI checkpoint byte for byte.
Property propositions, transaction models, and CEK bounds did not change.
The aggregate run retained `output/test.AsIZxSM3/summary.json` and per-suite logs.

## Workflow property-definition metadata

The workflow-scoped metadata checkpoint passed all eleven suites through
`./formal/plutus-upv test` in 306,824 ms including build. The new suite checks
shape validation, preserved missing/empty values, integer handling, catalogue
ID/version association, duplicate or wrong-primary rejection, and unchanged
generated statements. Reporter tests cover snapshot retention, metadata mismatch,
safe text display, and existing result-policy behavior.

Both CLI scenarios retain the selected definition in reports and execution
manifests; preparation failures retain it when lookup succeeds. The emitted
UP001 Types/Checks and UP012 Types/Tx/Checks match the preceding workflow
checkpoint byte for byte. The UP012 formulas and model remain unchanged.

An isolated Ajv 8.20.0 validator compiled the workflow JSON Schema and validated
both maintained records, including the intended acceptance of partial records.
Legacy catalogue schemas, records, and their validation scripts did not change.
The aggregate output is `output/test.FUFkwumk/`; issue #66 remains open for the
later rollout beyond the workflow.

# Workflow tests

The four reusable components have separate unit coverage. UP001, UP012, and UP015
are the three workflow scenarios; they reference candidate implementations
instead of defining candidate logic in the engine.

These experimental scenarios test integration; they do not establish general
readiness of the three properties or their transaction models.

[Aiken test projects](Projects/README.md) provide editable examples for manual
inspection. Start with [vault-demo](Projects/vault-demo/README.md) to see generated
UP-001 Lean files for passing and deliberately failing validators.

From `formal/`, run all workflow tests with verbose logs:

```sh
./plutus-upv test
```

With `formal/` on your shell's `PATH`, use `plutus-upv test` from any directory.
The runner builds explicit test targets, executes suites sequentially, and saves
logs and summaries under ignored `formal/output/test.XXXXXXXX/`. A build failure
stops the run; a suite failure allows the remaining independent suites to run.
Only a complete successful test run returns zero. Expected negative controls
print FAIL or INCONCLUSIVE without making their enclosing suite fail.

The aggregate command registers 20 suites, including component units, metadata,
run evidence, selection, shared source capture/compilation, relative review links,
output controls, and installer/launcher checks. It also runs real app/core solver cases, runner failure
controls, Input-to-Generator type-checking, Executor/Reporter solver controls, and
the scenarios below. Each scenario invokes its candidate-specific checks.
Optional manual integration probes are not additional suite runs.
Register new workflow test executables in `Runner.defaultSuites` so the aggregate
command includes them.

For focused scenario debugging:

```sh
lake exe workflow_up001_tests
lake exe workflow_up012_tests --unit
lake exe workflow_up012_tests
lake exe workflow_up015_tests --unit
lake exe workflow_up015_tests
lake exe workflow_single_check_tests
lake exe workflow_app_tests
lake exe workflow_selection_tests
lake exe workflow_sources_tests
lake exe workflow_review_tests
```

| Scenario | Coverage | Definition/model source |
| --- | --- | --- |
| [UP001](UP001/README.md) | Passing and failing vaults, invalid input, and timeout | `Candidates.UP001` and fixed demo inputs |
| [UP012](UP012/README.md) | Four original vesting propositions, native TxM-009 vault and reusable preparation checks, unsupported-profile handling, and a semantic negative control | `Candidates.UP012` plus test-owned vesting and vault profiles |
| [UP015](UP015/README.md) | Claim output swap, nonidentity applicability, shared-model app scenarios, unsupported-profile handling, and a counterfactual rejection control | `Candidates.UP015`, native TxM-007, and shared test-only linear-vesting preparation |

The UP001/UP012 scenario harnesses preserve the legacy `universal` CLI contract.
UP015 reuses `UP012/Inputs/plutus.json`, the same compiled validator, and TxM-007.
UP012 and UP015 `--unit` modes skip solver cases. Their default runs include
app scenarios and test-only negative controls. [Profiles/LinearVesting.lean](Profiles/LinearVesting.lean)
owns shared vesting preparation for UP012 and UP015.
The app control suite checks orchestration and terminal/index behavior. The
single-check suite runs actual compiled-validator goals through the app and core.
This reuses the existing solver cases.

[Unit checks](Unit/README.md) cover Input, generic Generator contracts, Executor,
and Reporter. The legacy executable names remain available for these checks and
existing integration controls.

The [single-check suite](SingleCheck/Tests.lean) checks the callable core, exact
selected theorem sets, assessment, and retained evidence. It runs UP-001 minting
against the passing/failing vaults and the UP-012 Claim/application pair through
the app and core APIs. `lake exe workflow_single_check_tests --unit` restricts that test executable
to adapter, assessment, and controlled-process checks without the real solver cases.

Inputs and expected declarations are permanent test fixtures. Generated Lean
sources, compiler artifacts, logs, and reports appear only in the local ignored
`formal/output/` folders after a CLI run. The [file map](../Docs/DEVELOPER-GUIDE.md#generated-goals-and-supporting-files) shows
where supporting definitions live.

`workflow_preparation_tests` adds pure compatibility and compiled-program admission
coverage. The aggregate now registers 20 suites. The new runtime scenarios in
UP012 use `preparation-demo`; the full UP-012 suite and the public CLI produced
the expected positive, negative, and failed-applicability outcomes. Existing vault-demo
expectations remain 30 selected combinations and 45 generated Lean files; this
pilot has not rerun that demo.

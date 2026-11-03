# Component unit checks

Run from `formal/`:

```sh
lake exe workflow_input_tests
lake exe workflow_generator_tests
lake exe workflow_executor_tests
lake exe workflow_reporter_tests
lake exe workflow_metadata_tests
lake exe workflow_evidence_tests
lake exe workflow_single_check_tests --unit
lake exe workflow_selection_tests
lake exe workflow_installation_tests
lake exe workflow_app_tests
lake exe workflow_runner_tests
lake exe workflow_executor_integration
lake exe workflow_reporter_integration
```

| Area | Coverage |
| --- | --- |
| `Input/Tests.lean` | Selection, metadata preservation, code decoding, and malformed inputs |
| `Selection/Tests.lean` | CLI controls, canonical selectors, registered model selection, and JSON property switches |
| `Installation/Tests.lean` | Installed launcher paths, caller-directory defaults, repeat installation, and preservation of existing commands |
| `App/Tests.lean` | Blueprint-wide orchestration, counts, continuation, checkpointed indexes, isolated files, and storage failures |
| `Generator/Tests.lean` | Generic contracts with stub providers, namespace validation, and empty plans |
| `Executor/Tests.lean` | Controlled compiler diagnostics, deadlines, output isolation, and process cleanup |
| `Reporter/Tests.lean` | Applicability qualification, trusted partial results, failure precedence, metadata integrity, and report files |
| `Metadata/Tests.lean` | Shape-only metadata parsing, preserved absence, catalogue association, and unchanged generated statements |
| `Evidence/Tests.lean` | Readable failed-input snapshots, invocation settings, read-once capture, and failure precedence |
| `Runner/Tests.lean` | Build failure blocks stale binaries, later suites continue after a failure, logs persist, and expected negative text can pass |

`workflow_generator_tests` runs only the generic Generator contract checks.
The UP001 and UP012 workflow suites run their own candidate-specific checks.
The [single-check suite](../SingleCheck/Tests.lean) provides controlled preparation,
assessment, binding, isolation, and evidence-failure checks. Its default command
also runs actual single-model solver cases through the app and core; `--unit` omits those cases.

The Input fixture preserves its original synthetic metadata and small decodable
program `480100002221200101`, from the pinned [script-encoding test](https://github.com/input-output-hk/PlutusCoreBlaster/blob/4ef48606303c45225d3ed2e2a87fc50280a763b7/PlutusCore/UPLC/ScriptEncoding/Tests.lean#L12).
It provides parser evidence rather than a validator proof.

`Fixtures/outcomes.lean.txt` is the unchanged shared real-solver control for
Executor and Reporter: one valid equation and one false quantified equation,
including indented counterexample values. `Reporter/Fixtures/summary.txt`
fixes the minimal text format for a synthetic observation. Neither fixture is
proof evidence for a Cardano validator. The solver controls retain Blaster's
SMT trust boundary.

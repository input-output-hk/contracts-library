# Legacy regression fixtures

These providers, catalogue records, invocation driver, and report formatter
preserve an independent comparison path for workflow tests. Maintainers use
property-owned `Run.lean` declarations for the current app.

| Location | Role |
| --- | --- |
| `Candidates/` | Older provider implementations and reviewed combination records |
| `Main.lean` | Bundled fixture invocation and report retention |
| `Driver.lean` | Test-only executable entry point |
| [Reporter/](Reporter/README.md) | Old report format used by assertions |

`Workflow.Tests.Support.invoke` runs the internal `workflow_legacy_fixture`
target. Tests still check its expected positive, negative, applicability,
input-error, timeout, and evidence outcomes. This fixture is not a client CLI;
use `plutus-upv run` and `plutus-upv test` for normal work.

Property formulas, model constructors, bounds, and reviewed limitation records
retain their existing meanings. This code is frozen comparison material, rather
than a second registration path to extend when adding a property.

[Validation](VALIDATION.md) records the cleanup's local regression and fidelity checks.

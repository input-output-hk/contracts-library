# Shared support and translator tests

This directory retains checks whose owner is a shared utility:

| Check | Purpose | Local command from `formal/` |
| --- | --- | --- |
| [ReturnDatum.lean](ReturnDatum.lean) | Structural checks for the shared return-datum predicate | `lake env lean tests/ReturnDatum.lean` |
| [test_process_blueprint.py](test_process_blueprint.py) | Regression tests for the separate blueprint translator | `python3 -B -m unittest discover -s tests -p test_process_blueprint.py` |

The translator tests use [fixtures/](fixtures/) and belong to the retained
translator tooling. The Plutus UPV runtime uses Lean.

Property-specific checks and fixtures live beside their owner under
`Formal/Properties/<category>/<code>/Tests/`. Earlier standalone candidates are
retained in `Tests/Standalone/`, with their recorded assumptions, expected
outcomes, and execution limits. See [the property bank](../Formal/Properties/README.md).

[Workflow tests](../Workflow/Tests/README.md) cover the app and engine.
Validator milestone suites live in each validator's `Tests/Main.lean`, alongside
its specification proof modules. The workflow aggregate does not implicitly run
every standalone candidate proof or validator milestone suite.

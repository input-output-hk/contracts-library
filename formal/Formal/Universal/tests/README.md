# M1.1 support and translator tests

**Command paths (2026-11-16).** Examples use the relocated M1.1 paths. See the
[migration validation](../../../MIGRATION.md) for the checks performed. Historical outcomes
retain their original revisions, models, and bounds. Run commands from `formal/`
unless a section says otherwise.

This directory owns checks for M1.1 support helpers and the retained translator:

| Check | Purpose | Local command from `formal/` |
| --- | --- | --- |
| [ReturnDatum.lean](ReturnDatum.lean) | Structural checks for the shared return-datum predicate | Build `Formal.Universal.Support.ReturnDatum`, then run `lake env lean Formal/Universal/tests/ReturnDatum.lean` |
| [test_process_blueprint.py](test_process_blueprint.py) | Regression tests for the separate blueprint translator | `python3 -B -m unittest discover -s Formal/Universal/tests -p test_process_blueprint.py` |

The translator tests use [fixtures/](fixtures) and belong to the retained
translator tooling. The Plutus UPV runtime uses Lean.

Prepare the return-datum test's import explicitly in a fresh build cache:

```sh
lake build Formal.Universal.Support.ReturnDatum
lake env lean Formal/Universal/tests/ReturnDatum.lean
```

Property-specific checks and fixtures live beside their owner under
`Formal/Universal/Properties/<code>/Tests/`. Earlier standalone candidates are
retained in `Tests/Standalone/`, with their recorded assumptions, expected
outcomes, and execution limits. See [the property bank](../Properties/README.md).

[Workflow tests](../Workflow/Tests/README.md) cover the app and engine.
Validator milestone suites live in each validator's `Tests/Main.lean`, alongside
its specification proof modules. The workflow aggregate does not implicitly run
every standalone candidate proof or validator milestone suite.

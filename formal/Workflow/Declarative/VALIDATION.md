# UP-012 experiment results

Local validation on the experiment branch, based on `80fb78f`. This validates the
new authoring path for UP-012, without completing the full migration in issue #110.

The model-list experiment changed exactly one file:
`Formal/Properties/Universal/UP012/Run.lean`. Discovery first listed TxM-007/008;
adding `"TxM-009"` to that list enabled the third combination. No catalogue,
model-selection branch, import template, or combination JSON changed in that step.

| Actual validator/model | Expected terminal result | Observed result |
| --- | --- | --- |
| Vesting Claim / TxM-007 | `PASS` | `PASS`; property and applicability Valid |
| Vesting Cancel / TxM-008 | `PASS` | `PASS`; property and applicability Valid |
| Normal vault / TxM-009 | `PASS` | `PASS`; property and applicability Valid |
| Deliberately buggy vault / TxM-009 | `FAIL` | `FAIL`; property Falsified, applicability Valid |
| Always-rejecting validator / TxM-009 | `ERROR` | `ERROR`; raw property Valid, applicability Falsified, qualified status `INCONCLUSIVE` |

All attempts used a 300,000 ms execution budget per combination and the unchanged
1,000,000 CEK-step property bound. Unsupported model/validator pairings remained
SKIPPED. Run-level errors were empty and no attempt timed out. The existing
workflow still defines the terminal categories and qualified results.

Six Python discovery checks passed. The new Lean tests passed model-list
selection, all three models' goal parity with the old adapter, metadata checks,
and invalid-registration controls. A kernel-checked equivalence confirms that
the emitted literal bound equals the existing `ledgerFuel`. The existing UP-012
unit suite also passed, including vault and reusable-preparation checks.

The experiment preserves the native `claim`, `cancel`, and `spend` constructors.
The two vesting artifact constants moved to a shared file without changing their bytes.
Generated headers, imports, and supporting aliases differ; the primary and
applicability formulae remain the same. New results also retain the property
`Run.lean` in their source snapshots.

Local evidence stays ignored under `formal/output/one-edit-validation/`:

- `before.json`: source hashes before the list edit.
- `result.json`: changed file names and the before/after model lists.
- `summary.json`: the list-edit check and all five runtime results.
- `before-list.*.log`, `after-list.*.log`: actual discovery output.
- `vault.*.log`, `vesting.*.log`, `always-reject.*.log`: invocation output.

The runtime evidence folders are `run.20261102T120900Z.z89NSt46`,
`run.20261102T121025Z.3uww5T88`, and `run.20261102T121242Z.X5G3fm1B`.
Each retains its generated Lean, compiler logs, input, results, and source index.

The experimental Python command works from a source checkout. The installed
product CLI and legacy candidate adapters remain available for comparison.
Other properties and admission methods need separate migration and validation.
The existing model coverage, applicability requirements, and SMT proof-trust
boundary continue to qualify these results.

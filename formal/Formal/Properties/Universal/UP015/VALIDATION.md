# UP-015 property-owned execution results

This second-property experiment builds on PR #111 at `0ce20fb`. All changes stay
inside `Formal/Properties/Universal/UP015/`. The existing shared generator,
discovery script, catalogue, model exports, UP-012 files, and Lake configuration
remain unchanged.

Adding [Run.lean](Run.lean) made discovery register UP-015 / TxM-007 alongside
the three existing UP-012 combinations. The property uses its original statement
and nonidentity applicability predicate with the existing Claim context builder.
Its argument list differs from UP-012's, requiring validity and acceptance without
a rejection predicate in the primary goal.

| Runtime check | Expected | Observed |
| --- | --- | --- |
| Original Claim output reversal | `PASS` | Property Valid; nonidentity applicability Valid |
| Test-only rejection after the same reversal | `FAIL` | Counterfactual property Falsified; nonidentity applicability Valid |

Both executions completed within a 300,000 ms budget and retained their generated
Lean and compiler logs. The CEK allowance remains 1,000,000 steps. The positive
run took 85,781 ms including app preparation; the negative control's executor
took 54,822 ms. These timings cover different execution boundaries.

[Tests.lean](Tests.lean) passed goal/name/expectation/model/support-link comparisons
against the legacy adapter, exact binding retention, shared-model selection by
two properties, automatic model imports, and rejection of the unsupported vault
combination. Kernel-checked equivalences cover the primary and applicability fuel
expressions. The property definition, metadata, native transaction model, and
input artifact remain unchanged.

The [negative-control definition](Tests/Controls.lean) belongs only to tests. Its
report carries a test-only property ID, with no official property definition or
combined-check binding. Its intentional property failure makes the control test
succeed; this is not a validator vulnerability claim.

Local ignored evidence lives under `formal/output/up015-declarative-validation/`:
`positive.json`, `negative-control.json`, their stdout/stderr logs, and
`unchanged-shared-sources.json`. The actual runs are
`run.20261102T141628Z.V2bMAfRu` and `run.6GbfqQK5`. The positive run also retains
the property's `Run.lean` in its shared source snapshots.

The original model restrictions and proof-trust boundary still apply. This check
covers the two-output Claim swap for admitted vesting artifacts. It does not
establish arbitrary permutation coverage or require index-sensitive validators
to accept an unchanged redeemer after reordering. The installed CLI still uses
its existing path; the prototype's all-export startup limitation remains.

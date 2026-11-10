# UP-000 native integration validation

This record covers implementation commit
`ec0b8bfb18ad77fb548ee2c3402d8c25f5b212e5`, based on foundation `1d3f55e`.
The checks ran on 2026-11-10 with Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | `7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc` |
| PlutusCore | `4ef48606303c45225d3ed2e2a87fc50280a763b7` |
| Blaster | `402f6d22c1fc42e6e26255faac77e15b2450e4ab` |

## Results

| Check | Observation |
| --- | --- |
| Native property/parity build and unit suite | Passed |
| Kernel equivalences | Claim/Cancel context mappings in both directions, evaluator interface, and existential statements checked |
| Native app integration | Two PASS checks, each with one Valid existential obligation |
| Unsupported vault | Two SKIPPED checks with unsupported reasons and no generated modules |
| Second vesting artifact | Two SKIPPED checks with the property exclusion reason and no generated modules |
| Synthetic always-error controls | Two Falsified/FAIL results, as required by the controls |
| Full `./plutus-upv test` | All 27 suites passed; 963.352 seconds |
| Public `./plutus-upv run … --check UP-000` | Two PASS results; 57.032-second app execution; exit 0 |

The initial native app scenario completed in 56.294 seconds. It retained six
generated Lean files across two check directories, exact property/model bindings,
compiler logs, and a shared source snapshot. Its two obligations were
`someAccepted_claim` and `someAccepted_cancel`; neither had a separate
applicability obligation.

The separate public CLI invocation used the documented original-fixture command.
It retained both Valid observations, all six generated Lean sources and their
compiler logs, the exact input snapshot, and compiled shared-source snapshots.
The reported app elapsed time excludes launcher preparation.

The controls preserve the model constructors, proposition, validity predicate,
argument encoding, and 1,000,000-step bound. They replace the evaluated program
with a synthetic always-error program, use separate control identities, and
clear official property/binding metadata. Their original blueprint is retained
only as a labeled reference input.

All 298 captured source/configuration hashes matched after the regression run.
Shared generator and preparation code, transaction models, and historical
standalone proof and control files have no changes in this integration.
Focused Astra source and retained-evidence review found no unresolved findings.

## Interpretation

The current obligations preserve the older standalone formulas under the
current dependency pins. Historical results under earlier dependency revisions
remain separate records. Context and evaluator equivalences are kernel-checked;
the emitted source-literal correspondence is checked by the property unit suite.
Generated acceptance results retain Blaster's `blasterProven` SMT trust boundary.
The existing CEK dependency admission warning remains visible during builds.

These results cover the original compiled vesting artifact with TxM-007 Claim
and TxM-008 Cancel. They do not establish arbitrary action coverage or full
ledger reachability. Symbolic script credentials, transaction shapes, and the
CEK bound remain unchanged. The integration adds no minimum-ADA condition and
prints no accepted transaction witness. Issues #22 and #96 retain the broader
work. UP-009/UP-016 proof attempts and separate milestone proofs were not run.

See the [property guide](README.md) for the run command and scope. Generated
sources, logs, and run snapshots remain local under ignored `formal/output/`.

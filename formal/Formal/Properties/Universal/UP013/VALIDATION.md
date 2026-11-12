# UP-013 native integration validation

UP-013 passed the targeted checks below on 2026-11-11. Implementation commit
efbfb2c709a4f7f0cd637557a10b9001381dee38 records the tested source, based on
foundation 62d8d3c. The environment used Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-013 property build and unit suite | Passed; 516 build jobs |
| Affected app/test build | Passed; 616 build jobs |
| Kernel equivalences | Original range helpers, both main formulas, and both applicability formulas checked |
| Native app integration | Two PASS checks supported by four Valid observations; 89.835 seconds |
| Unsupported vault | Two SKIPPED results with unsupported reasons; no generated modules |
| Second vesting artifact | Two SKIPPED results with the property exclusion reason; no generated modules |
| Synthetic always-accepting controls | Both main obligations Falsified/FAIL; both applicability obligations Valid/PASS |
| Applicability qualification controls | Missing, inconclusive, or falsified support prevented a Valid main observation from establishing PASS |
| Affected regressions | Existing UP-012 and UP-004 property suites, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Separate public UP-013 CLI run | Two PASS checks, four Valid obligations, 92.284-second app execution, and exit 0 |

The new property and workflow suites plus seven affected regression suites passed.
The aggregate registers 31 suites; this change did not run the full aggregate.

## Evidence and controls

The native app run retained six generated Lean files across the two check
directories, exact input and property/model bindings, compiler logs, and shared
source snapshots. Its four obligations were `unboundedRange_claim`,
`unboundedRange_claim_applies`, `unboundedRange_cancel`, and
`unboundedRange_cancel_applies`. Each main result retained its own model's
applicability link.

The separate public CLI invocation used the documented original-fixture command.
It retained four complete Valid observations with the same model-specific links,
six generated Lean files and their compiler logs, the exact input snapshot, and
18 compiled shared-source snapshots. Its app elapsed time excludes launcher
preparation.

The synthetic controls replace the program with an always-accepting unit-returning
lambda while retaining the model, range mutation, premises, argument encoding,
and 1,000,000-step bound. Main rejection is falsified while its applicability
remains valid. Separate control target identities and null official
property/binding metadata prevent attribution to the original validator. The
original blueprint remains only a labeled reference input.

Qualification controls use in-memory observations over the generated plans.
They test the assessor's policy, not execution of a validator or a solver proof.
A controlled Valid main result is inconclusive when its linked applicability is
missing, inconclusive, or falsified; Valid support provides the positive control.
These controls create no execution evidence or official property result.

The pure tests preserve both directions of the original Claim/Cancel model
mapping, the mutation's unchanged fields, and all four propositions. One Cancel
equivalence uses a local elaboration-depth setting of 2048. It changes neither
the CEK bound nor the statement. Native range helpers have the same bodies as
the historical helpers without importing unrelated model implementations into
the property definition.

All 315 captured source/configuration hashes matched after targeted validation.
The initial app suite ran before the implementation commit and records a dirty
62d8d3c checkout. The source manifest and captured module sources match the
implementation commit; the Git label alone does not identify that tested source.
Shared generator, assessor, preparation code, transaction models, dependency
pins, and historical standalone proof/control implementations are unchanged.
The old standalone guide gained only a link to the native route.

## Interpretation

The obligations preserve the original scoped formulas under the current
dependency pins. Historical results under earlier pins remain separate records.
Formula and helper equivalences are kernel-checked; the property unit suite
checks generated source literals and bindings. Generated results retain
Blaster's `blasterProven` SMT trust boundary and the existing CEK dependency
`sorry` warning.

These results cover the original vesting artifact with TxM-007 Claim and
TxM-008 Cancel. The mutation replaces the whole validity interval with
`(-infinity, +infinity)`; it does not cover every interval missing a lower bound.
The rule is not a requirement for all validators. Model-validity premises and
applicability do not establish deployed-ledger reachability or arbitrary
transaction coverage. No new nonidentity premise, model constraint, minimum-ADA
condition, or printed transaction witness was added. Issues #34 and #96 retain
the broader work. UP-009/UP-016 proof attempts and separate milestone proofs
were not run.

See the [property guide](README.md) for commands and scope. Generated sources,
raw logs, and snapshots remain local under ignored `formal/output/` folders.

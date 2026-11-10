# UP-004 native integration validation

UP-004 passed the targeted checks below on 2026-11-10 at implementation commit
72b1f9eadafb2786d9bb2c698b0f933fb5c4704f, based on foundation 84087cf.
The environment used Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-004 property build and unit suite | Passed; 510 build jobs |
| Affected app/test build | Passed; 605 build jobs |
| Kernel equivalences | Claim/Cancel context mappings, rejection evaluator, and existential statements checked |
| Zero-fuel controls | Initial-state exhaustion cannot establish rejection or rejection existence |
| Native app integration | Two PASS results, each with one Valid existential obligation; 54.500 seconds |
| Unsupported vault | Two SKIPPED results with unsupported reasons; no generated modules |
| Second vesting artifact | Two SKIPPED results with the property exclusion reason; no generated modules |
| Deliberate 1 ms execution budget | Two TIMEOUT results, internally INCONCLUSIVE; generated sources, logs, and bindings retained |
| Synthetic always-accepting controls | Two Falsified/FAIL results, as required by the controls |
| Affected regressions | Existing UP-000 property suite, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Separate public UP-004 CLI run | Two PASS results; 58.887-second app execution; exit 0 |

The new property and workflow suites plus six affected regression suites passed.
The aggregate registers 29 suites. This change did not rerun the full aggregate;
the preceding merged UP-000 checkpoint records its own 27-suite run.

## Evidence and controls

The public CLI invocation used the [documented command](README.md). It retained
six generated Lean files across the Claim/Cancel directories, both complete Valid
observations, compiler logs, the exact input snapshot, and 18 compiled shared-source
snapshots. Its app elapsed time excludes launcher preparation. The obligations
were `someRejected_claim` and `someRejected_cancel`, with no separate applicability.

The 1 ms control interrupted `Generated/Types.lean` compilation before solver
execution. It verifies execution-deadline reporting and incomplete evidence
retention; it does not demonstrate a timeout inside the solver. This wall-clock
control is separate from the zero-CEK-step semantic checks.

The synthetic controls replace the program with an always-accepting unit-returning
lambda while retaining the models, rejection-existence claim, validity predicate,
argument encoding, and 1,000,000-step bound. Their expected Falsified results mean
that no context satisfies the rejection-existence claim for that control program.
Separate control identities and null official property/binding metadata prevent
attribution to the original validator. The original blueprint remains only a
labeled reference input.

All 306 captured source/configuration hashes matched after the runs. Shared
generator/preparation code, transaction models, and historical standalone proof
and control files have no implementation changes in this integration. The old
standalone guide gained only a link to the native route.

## Interpretation

The obligations preserve the older standalone formulas under the current
dependency pins. Historical results under earlier pins remain separate records.
The context/evaluator/statement equivalences and zero-fuel facts are kernel-checked;
the property unit suite checks emitted source literals. Generated results retain
Blaster's `blasterProven` SMT trust boundary and the existing CEK dependency
`sorry` warning.

These results cover the original compiled vesting artifact with TxM-007 Claim
and TxM-008 Cancel. They establish bounded model-valid explicit rejection, without
establishing that all invalid transactions reject, authorization is correct, or
the rejected contexts are reachable on the deployed ledger. Symbolic script
credentials and transaction shapes remain unchanged. No minimum-ADA condition
or printed rejected-transaction witness was added. Issues #25 and #96 retain
the broader work. UP-009/UP-016 proof attempts and separate milestone proofs
were not run.

Generated sources, raw logs, and snapshots remain local under ignored
`formal/output/` folders.

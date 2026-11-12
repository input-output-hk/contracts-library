# Lean-only property authoring validation

The Lean-only implementation was tested at `a981eaabd5e862ceba8f65d260bea179b1f6eb3d`,
based on merged foundation `34272d42d17bd2fab73fea231f7dc42631e7bf52`.
All 519 tracked source hashes were unchanged after validation.

## Environment

| Component | Revision |
| --- | --- |
| Lean | 4.24.0 |
| Z3 | 4.15.2 |
| CardanoLedgerApi | `7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc` |
| PlutusCore | `4ef48606303c45225d3ed2e2a87fc50280a763b7` |
| Blaster | `402f6d22c1fc42e6e26255faac77e15b2450e4ab` |

## Executed checks

`./plutus-upv test` passed all **25 suites**. The outer command completed in
873.300 seconds, including the executable build. Its runner summary records
871.476 seconds.

The aggregate includes independent legacy solver controls and new Lean discovery,
property-binding, CLI, and installer checks. The following additional public CLI
runs exercised actual proofs through the new launcher:

| Public command case | Observed result | Command elapsed |
| --- | --- | --- |
| UP-001, normal and buggy vaults | Normal: 5 PASS and 1 SKIPPED. Buggy: 5 expected FAIL and 1 SKIPPED. | 208.060 s |
| UP-012, three reusable programs | Controller: 1 PASS. Missing-signature control: 1 expected FAIL. Never-accepting control: 1 ERROR from false applicability. Each also has 2 unsupported SKIPPED pairings. | 62.909 s |
| Vesting UP-012 and UP-015 | 3 PASS and 1 incompatible pairing SKIPPED. | 148.906 s |

All three invocations completed with product exit `0`, which records completed
orchestration. Validation separately checked the saved indexes, individual
obligations, expected observations, complete evidence, and terminal categories.
The never-accepting validator received no passing property result.

Across these runs, all 25 selected combinations retained their exact reviewed
pairing limitations. Executed checks retained `Types.lean`, `Tx.lean`,
`Checks.lean`, and the discovery snapshot. The spending purpose of UP-001
intentionally skipped on the declared spending targets.

Reproduce from `formal/`:

```sh
./plutus-upv test
./plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json --check UP-001 --timeout-ms 300000
./plutus-upv run Workflow/Tests/UP012/Inputs/reusable.json --check UP-012 --timeout-ms 300000
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --validator linear_vesting.linear_vesting --check UP-012 --check UP-015 --timeout-ms 300000
```

## Focused controls and review

The three property unit suites passed, including exact comparisons of all ten
bindings against frozen pre-refactor limitation records. Discovery controls
covered malformed and duplicate identities, actual typed model exports, broken
unselected sources, exact selection bytes, shared preparation deadlines, startup
marker races, raw exit retention, descendant cleanup, and log-write failure.
Public smoke tests covered default selection, disabled checks, caller paths with
spaces, CRLF switches, and declared-purpose skipping. The installer and a public
unsupported-input run succeeded with Python absent from `PATH`.

Focused Astra reviews found no remaining blocker in property/model fidelity or
runtime selection, deadline, and error-evidence handling after fixes. Review
was source inspection; the execution results above provide separate evidence.

Raw command receipts, compiler output, run indexes, and source hashes remain local
under ignored output/evidence directories. Normal app runs retain their own
`run.json`, `discovery.json`, generated Lean, source snapshots, and logs.

## Scope

These results cover the existing three properties, ten maintained pairings,
and their current admission policies. They preserve the 5,000,000-step UP-001
bound and 1,000,000-step UP-012/UP-015 bounds. A bounded PASS does not establish
general validator safety or deployed-ledger reachability.

The app requires a source checkout. Older prototype validation records describe
their own revisions and Python coordinator. UP-009/UP-016's held proofs were not
run. Existing CEK admission warnings and Blaster's SMT trust boundary remain.


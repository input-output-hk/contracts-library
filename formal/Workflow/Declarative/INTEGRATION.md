# Public CLI integration validation

This file preserves historical prototype evidence. The current Lean-only authoring
path is documented in [README.md](README.md). The results below used their recorded
source and dependency revisions, including the earlier Python coordinator; they
do not establish validation of the current implementation. Fresh results are
recorded in [Lean-only authoring validation](LEAN-VALIDATION.md).

This historical record describes `0e176dd`. UP-001 now has its own
[run declaration](../../Formal/Properties/Universal/UP001/Run.lean).

The `feat/declarative-cli-integration` branch builds on `f14d71e`. The public
`plutus-upv run` command now selects property-owned UP-012/UP-015 declarations;
UP-001 uses its existing generator through a compatibility bridge.

Discovery evaluates selected `Run.lean` files in Lean, then compiles only the
model names those declarations return. Evaluator helpers moved to
`Formal/Support/Execution.lean`; the current support-folder cleanup updates
their module paths and declaration namespaces while preserving their definitions.
The public entry point no longer imports the candidate catalogue or model-bank
aggregate. Explicit module imports remain dependencies.

| Public-command case | Verified outcome |
| --- | --- |
| Vesting UP-012 and UP-015 together | Three `PASS`, one incompatible model `SKIPPED` |
| Normal and deliberately buggy vaults | Expected `PASS` and `FAIL`; incompatible vesting models `SKIPPED` |
| Always-rejecting validator | `ERROR` from false applicability, with no passing property verdict |
| Legacy UP-001 with declarative UP-015 | Five normal-vault `PASS`, five buggy-vault `FAIL`; other pairings `SKIPPED` |
| Default selection on an unsupported parameterized fixture | All ten current combinations present and `SKIPPED` |
| Broken unused TxM-009, invalid unused TxM-999, and broken unselected property | Selected UP-015 still runs and reports the unsupported input as `SKIPPED` |
| Broken selected property | Nonzero startup exit; preparation diagnostics retained; no proof result |
| One-millisecond verification budget | `TIMEOUT`, qualified inconclusive result, and execution evidence retained |
| All properties disabled | Successful no-op, zero checks, and no passing verdict |
| Caller paths containing spaces and CRLF selection JSON | Correct caller-relative paths and exact retained selection bytes |

The first public integration invocation passed nine test methods with real proof
cases. The default-selection method passed separately after its addition. The
registered smoke suite reruns the non-proof cases, including the timeout control;
the real proof cases require `--proofs`.

Fifteen Python discovery/selection/deadline tests passed. Native selection,
orchestration, declarative UP-012/UP-015 goal parity, and legacy UP-012/UP-015 unit
checks passed. Installer/launcher checks passed, including missing-Python handling.
Runner controls and the newly registered test executables passed. The aggregate
now registers 24 suites; the full 24-suite aggregate was not rerun for this change.

The existing transaction constructors and primary/applicability formulas remain
the same. UP-012's import now uses the model-independent evaluator module.
The public checks preserve the existing 1,000,000-step UP-012/UP-015 allowances
and 5,000,000-step UP-001 nonacceptance bound. Actual proof attempts used a
300,000 ms budget per combination; the timeout case deliberately used 1 ms.

Local evidence stays ignored under `formal/output/cli-integration-validation/`,
`formal/output/public-cli.s17j6oid/`, and `formal/output/public-cli.wl8wvzk7/`.
The summary links each real app run to its input, generated modules, compiler
logs, results, and shared source snapshots. Successful app runs retain a frozen
`discovery.json`; startup failures retain their separate preparation index/logs.

## Remaining limits

The checkout-backed public command now requires Python 3.9 or newer. The installer
checks for Python; the Nix development shell includes it. Nix syntax parsing
passed, but the full development shell was not rebuilt. Managed runtime packaging
remains separate work.

Model export/path conventions and the supported admission methods still apply.
A selected source that cannot compile stops preparation with an error. Default
selection requests every available property, so errors in that requested set
remain visible. UP-001 retains its fixed purpose imports until its own migration.
Legacy candidate/profile files remain for compatibility and regression comparisons.
This integration does not widen transaction coverage, infer protocol relevance,
change the SMT proof-trust boundary, or complete every part of issue #110.

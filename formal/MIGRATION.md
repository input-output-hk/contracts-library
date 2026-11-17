# Milestone layout migration

M1.1's universal-property app, banks, support, and retained candidates now live
under `Formal/Universal`. M1.2's specification proofs and milestone tests live
under `Formal/LinearVesting`. The small `Formal/Shared` area contains the common
evaluation predicates and generic process utility used across milestones.

The migration preserves one Lake workspace and the public command names.
Lean import names and source paths change; code importing the previous paths
must use the mappings below. Property IDs, definition versions, categories,
transaction-model IDs, mathematical statements, model domains, and execution
bounds are unchanged.

## Source map

| Previous path or namespace | Current path or namespace |
| --- | --- |
| Formal.Properties.Universal.UPxxx | Formal.Universal.Properties.UPxxx |
| Formal.Properties.Common and category/index facade | Formal.Universal.Properties.Common and one Index |
| Formal.TxModels | Formal.Universal.TxModels |
| Workflow | Formal.Universal.Workflow |
| Formal.Support | Formal.Universal.Support |
| Formal.Theory | Formal.Universal.Theory |
| Formal.Vesting.Linear.Blueprint | Formal.Universal.Standalone.LinearVesting |
| Formal.Vault.Blueprint | Formal.Universal.Standalone.Vault |
| Formal.Settings.Blueprint | Formal.Universal.Standalone.Settings |
| Formal.Vesting.Linear, excluding Blueprint | Formal.LinearVesting |
| Formal.Common | Formal.Shared.Common |

Properties use direct folders such as `Formal/Universal/Properties/UP001`.
Their categories remain in metadata. The retained validator-specific candidate
fixtures belong to M1.1 even when they use a vesting validator.

M1.1 guides, translator, and utility tests moved under its `docs`, `scripts`,
and `tests` directories. Its example switches are now
`Formal/Universal/checks.example.json`. The legacy translator's default output
is `Formal/Universal/Standalone/Blueprint`; explicit output selection remains.
The M1.2 log-annotation helper moved under `Formal/LinearVesting/scripts`.

From `formal/`, the public entry points remain:

```sh
./plutus-upv test
lake exe test_m12 --list
```

The first command runs the maintained M1.1 aggregate. The second lists M1.2
targets without executing them. A bare `lake build` retains its existing
combined Formal target and can run real milestone proofs; the validation below
used explicit app/support/test targets instead.

## Shared process boundary

M1.2's runner no longer imports the universal workflow or its property metadata.
It uses `Formal.Shared.Process` and a small local progress-output helper.
M1.1 keeps its Executor interface through typed aliases and a narrow adapter.
Process deadlines, environment overrides, working directories, process-group
termination, exit observations, and invocation evidence keep their prior behavior.

`Formal.Shared.Common` retains its 5,000,000-step nonacceptance predicate.
M1.1's explicit rejection predicate remains separate and excludes fuel exhaustion.
The migration does not substitute one meaning for the other.

## Validation record

Implementation checkpoint: `3ee26eeb63ec53f0e55e3ec9e874f0d7f668914e`, based on
foundation `a8238110cb51a44623ae0bdabc637452daf872b2`. Checks ran on 2026-11-16
with Lean 4.24.0 and Z3 4.15.2. Dependency pins remain ledger 7b743af,
PlutusCore 4ef4860, and Blaster 402f6d2.

| Check | Result |
| --- | --- |
| Source preservation | 267 existing Lean files match the explicit path/namespace substitutions; four process/runner files received separately reviewed changes |
| Frozen files | All 100 protected artifact/configuration files retain their original hashes |
| Runtime snapshot | 352 source/configuration hashes captured before execution |
| Support/app build | Passed, 605 jobs |
| Maintained test-target build | Passed, 841 jobs, including the controlled M1.2 runner target |
| Controlled M1.2 runner | Passed; no real validator proof modules executed |
| Legacy translator | 47 tests passed |
| Metadata/tooling | 110 Node tests passed, including seven real-Lean synthetic axiom-policy controls |
| Maintained workflow aggregate | 38/39 passed in 1616.140 seconds; only the moved installer fixture failed |
| Installer repair | Its one-line parent-directory correction passed the affected suite; the other 351 runtime hashes are unchanged |
| Public CLI check | UP-008 returned qualified FAIL with Falsified/Valid observations, complete evidence, 91.966-second app execution, and exit 0 |
| M1.2 listing | Printed the five targets with their new module names without running their proofs |
| Return-datum structural checks | Ten kernel examples passed after explicitly building their support import |

Initial compilation exposed field-notation compatibility in the extracted type
aliases; typed wrappers resolved it without changing diagnostics or process
behavior. The temporary-directory Node controls initially selected the machine's
global stable toolchain and failed during a download, with disk pressure also
interrupting binary linking. Those attempts supplied no proof result. The tests
now select the repository toolchain and bound each synthetic Lean case to thirty
seconds; the pinned retry and target rebuild passed.

The return-datum check initially lacked its support module's compiled import.
Building that module and rerunning the structural examples passed; the current
test guide now includes this prerequisite. That check does not execute UP-006's
validator statement or any held proof attempt.

The aggregate ran from clean implementation commit 3ee26ee. The failing shell
fixture still walked four parent directories after relocation and looked for
install.sh inside Formal/Universal. Commit e231b7e6674703addeb88769d4588f0935afeec9
changes only that fixture to walk six parents. The production installer and
launcher did not change. Its targeted rerun passed; all other 38 aggregate suites
had passed, including their solver scenarios. This is aggregate evidence plus
a passing repair run, not a single green aggregate execution on the final head.

The separate public CLI ran from clean commit e231b7e. Its UP-008 result retained
Falsified main/Valid applicability and complete evidence with the exact support
link. Three generated Lean files, compiler logs, exact input snapshots, and 18
compiled source snapshots remain. Source and compiled-file hashes match the
saved index; source hashes match the implementation. App timing excludes launcher
preparation. The runtime manifest retains 352 entries, with only the installer
fixture differing from the aggregate's earlier snapshot.

Historical validation records preserve their old revisions, measurements, and
trust boundaries. Their migration notes distinguish old commands from current
paths; moving a source does not renew its historical proof result. The existing
CEK dependency `sorry` warning and Blaster SMT trust remain. The controlled runner
fixtures intentionally exercise detection of admitted proofs.

## Pending branch integration

This layout change does not integrate main or M1.2 PR #16. Private no-commit
previews from the implementation checkpoint found:

| Incoming branch | Textual result |
| --- | --- |
| main at 6868c537 | Clean automatic merge |
| M1.2 base at 11207fe | One new-file location conflict |
| PR #16 at 9f7a403 | Three content and six new-file location conflicts |

Git relocates new M1.2 files but does not rewrite their Lean imports or namespaces.
PR #16 still needs its references updated to `Formal.LinearVesting` and
`Formal.Shared.Common`, including its property catalogue and explicit runner
coverage for accepted new proof modules. The metadata/specification snapshot
decision and main's changed validator artifacts remain separate work.

No real M1.2 proofs or held UP-009/UP-016 attempts ran. The global installed CLI
was not retargeted; use this checkout's explicit command when validating it.
Raw test logs, generated sources, merge previews, and run records remain local
and ignored. The [workspace guide](README.md) links the current milestone guides.

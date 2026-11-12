# Run Plutus UPV

Plutus UPV (Universal Property Verifier) checks universal properties against
compiled Plutus validators using Lean and configured proof tools. The prototype
accepts the documented Aiken-style Plutus V3 blueprint profile. By default, one
command processes all logical validators and all eighteen registered property/model
combinations. They comprise two for UP-000, six for UP-001, two for UP-004,
one for UP-011, three for UP-012, two for UP-013, one for UP-014, and one for UP-015.

These are experimental workflow bindings; registration does not establish general readiness
of the properties or models.

The app prints a terminal summary and retains local run files. The separate
human-friendly final report remains future work in
[issue #83](https://github.com/no-witness-labs/contracts-library/issues/83).

## Prepare once

Have Lean **4.24.0**, Z3 **4.15.2**, GNU coreutils (`timeout`, `mktemp`,
`date`, and `sha256sum`), and Git on `PATH`. From the repository root:

```sh
./formal/install.sh
```

The installer builds the app and links `~/.local/bin/plutus-upv` to this checkout.
Keep the checkout in place: it supplies the app, metadata, and Lean dependencies.
If that bin directory is outside your `PATH`, the installer prints the shell
command to add it. It does not edit shell configuration. Use `--bin-dir DIRECTORY`
to choose another location. Repeating the installation for the same checkout is
safe; the installer refuses to replace an unrelated existing command.

You can also use `./plutus-upv` directly from `formal/`. The launcher resolves
input and selection-file paths from your calling directory, then uses the app's
Lean environment. From `formal/`, `lake exe plutus-upv ...` also works.

The first build can download and compile dependencies. Lake uses revisions in
the committed `lake-manifest.json`; reserve `lake update` for intentional upgrades.
The launcher also builds the command when needed and prepares selected checks
internally. Users keep the same command.

## Run and select work

From a directory containing `plutus.json`, run:

```sh
plutus-upv run
```

The default timeout is **5 minutes per validator/check combination**. Input
defaults also work with selection flags, for example `plutus-upv run --check UP-001`.
Run files remain under this app checkout's `formal/output/`; the terminal prints
their location. The command leaves the input project unchanged.

Run all validators and registered combinations:

```sh
plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json --timeout-ms 120000
```

Select one validator and one property:

```sh
plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json --validator vault.vault --check UP-001 --timeout-ms 120000
```

The earlier positional form also works:

```sh
plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json vault.vault --check UP-001 --timeout-ms 120000
```

`--validator` and `--check` may repeat. Use the full `module.validator` name or an
unambiguous short name. Entries for several handlers form one logical target.
Selection preserves blueprint and property-declaration order and runs each combination once.
The app captures the blueprint once and prepares each selected validator once.
A malformed compiled artifact produces that validator's preparation error while
other validators continue. Invalid shared JSON/title structure stops discovery.

## Select properties with a file

Start with [checks.example.json](../../checks.example.json), which enables all eight
registered properties, or save your own `checks.json`. For example, enable only UP-001:

```json
{
  "UP-000": false,
  "UP-001": true,
  "UP-004": false,
  "UP-011": false,
  "UP-012": false,
  "UP-013": false,
  "UP-014": false,
  "UP-015": false
}
```

```sh
plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json --checks-file checks.json
```

Without a file or `--check`, all registered properties run. With a file, only
properties explicitly set to `true` run; `false` and omitted properties stay off.
Each enabled property selects all its registered model combinations. Clients do
not supply transaction models.

Unknown IDs, nonboolean values, and malformed files fail before verification.
Do not combine `--check` with `--checks-file`. An empty enabled set is a valid
no-op: the terminal says that verification did not run, and no check results
claim a pass.

## Read the terminal and run files

The terminal table shows PASS, FAIL, SKIPPED, ERROR, and TIMEOUT counts per
validator. A key immediately below the table explains each term. SKIPPED combines
attempts with no applicable obligations and unsupported validator/model pairs.
TIMEOUT identifies unresolved verification that exceeded the executor's time
limit. ERROR means no reliable result for another reason, including invalid plans,
unestablished applicability, missing evidence, and preparation or storage failures.
Operational failures take precedence over a recorded timeout.

Each count represents one property/version/model combination; supporting
applicability obligations do not add extra checks. The app also prints recorded
check counts, elapsed time, errors, and output paths. Open the printed `Review`
path (`README.md`) to browse relative links to generated Lean, check results,
logs, and shared source snapshots. `Index` points to the machine-readable
`run.json`. The app assigns no overall verification verdict.

These are terminal categories. The saved check assessment retains its existing
PASS/FAIL/INCONCLUSIVE status. `run.json` preserves the separate `not_run` reasons
(`not_applicable` and `unsupported`) and a guarded `timed_out` flag. The app derives
the terminal groups from these typed facts, rather than parsing reason text.

Each invocation creates a fresh local folder:

```text
output/run.<timestamp>.<unique-id>/
├── README.md
├── run.json
├── discovery.json                     # selected preparation steps and retained diagnostics
├── sources/
│   ├── index.json
│   ├── Formal/                          # imported project Lean sources and compiled modules
│   ├── _logs/                           # supporting-source compilation
│   ├── lean-toolchain
│   ├── lake-manifest.json
│   └── lakefile.toml
├── input.json
├── checks.json                         # when a selection file was supplied
└── validators/
    └── vault.vault/
        └── UP-001-v1-TxM-001/
            ├── check-result.json
            ├── input.json
            ├── execution.json
            └── Generated/
                ├── Types.lean
                ├── Checks.lean
                └── compiler outputs and logs
```

Preparation diagnostics also remain under `output/discovery.<unique-id>/`.
If a selected source cannot compile, the command exits with code 2 and prints
that evidence path before verification starts. Broken unselected sources do not
block explicitly selected checks.

Earlier runs remain intact, and Git ignores the output. Folder names encode
characters such as `/`; `run.json` preserves canonical validator names.

| File | Contents |
| --- | --- |
| Root `README.md` | Relative links to retained files and recorded results; refreshed at each checkpoint |
| `sources/` | Shared imported project sources, compiled modules, source-compilation logs, and environment records |
| `sources/index.json` | Source hashes, imports, compilation state, toolchain/configuration hashes, and dependency revision/dirty-state records |
| `run.json` | Invocation/options, selected work, result-file references, errors, elapsed time, and completion marker; updated as work progresses |
| Root `input.json` | Captured readable blueprint, including input that later fails validation |
| Root `checks.json` | Supplied selection-file snapshot, when present |
| Per-check `check-result.json` | The assessed six-field result, including scope, reasons, and evidence references |
| Per-check `input.json` | The same captured blueprint used to prepare that validator |
| Per-check `execution.json` | Attempted commands, timing, raw observations, and diagnostics |
| `Generated/` | Generated Lean, stdout/stderr logs, and successful compiled modules; UP-000, UP-004, UP-011, UP-012, UP-013, UP-014, and UP-015 also generate `Tx.lean` |

An interrupted run can leave its last saved index unfinished. Files depend on how
far an attempt progressed: unreadable input has no snapshot, and validator
preparation errors have no generated proof files.

The app captures and compiles supporting project definitions such as `EveryMint`
and `EveryWithdraw`, including their transitive project imports, once per run as
needed. Generated checks use those captured modules. External libraries still
use the installed Lean environment. The records include their configured pins,
actual checkout revisions, and tracked dirty state. Dependency sources and the
runtime remain outside the bundle.

Independent replay remains future work. See the
[check file map](DEVELOPER-GUIDE.md#generated-goals-and-supporting-files).
The navigation README is separate from the future final client report. The new
command does not generate legacy `report.json`/`report.txt` files.

## Time limits and exit codes

The default execution limit is 5 minutes **per validator/check combination**.
`--timeout-ms 120000` gives each combination up to 120 seconds across its generated
modules. Supporting-source preparation has a separate compilation budget of the
greater of the selected timeout and 30 seconds. It does not consume the proof
budget. Setup and file retention add overhead. These limits are separate from
the property's CEK-step bound.

Individual failures, unsupported checks, and timeouts
retain their outcomes while independent checks continue. A supporting-source
capture or compilation failure retains available generated sources, source logs,
and the source index, records INCONCLUSIVE, and counts as an app operational error.
Because the source bundle is shared, a preparation failure prevents later generated
checks from executing in that run. Their generated files and explained INCONCLUSIVE
results are still retained; start a fresh run after correcting the source problem.

| Product exit | Meaning |
| --- | --- |
| `0` | The app completed and retained the selected work, including ordinary FAIL or INCONCLUSIVE outcomes |
| `2` | Input, validator preparation, catalogue, app, or storage errors prevented normal completion/retention |

A zero exit code does not assert that properties passed; inspect the table and
result files. The former `universal` entry point is retired. Use `plutus-upv run` for
verification and `plutus-upv test` for local workflow checks.

## Property scope and examples

Run UP-000 against the original reference vesting fixture from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-000
```

This selects Claim (TxM-007) and Cancel (TxM-008). Each checks for a model-valid
accepted context within **1,000,000 CEK steps**, using one existential goal and
no separate applicability obligation. The expected reference outcome is two PASS
results when both goals complete successfully. Inspect the actual table and
retained files to determine the run's outcome.

Open the printed `Review` path. Each `UP-000-v1-TxM-007` or `UP-000-v1-TxM-008`
folder contains generated `Types.lean`, `Tx.lean`, and `Checks.lean` plus results
and logs. The checks are `someAccepted_claim` and `someAccepted_cancel`.

UP-000 admits only this original compiled artifact; its run declaration skips
the second artifact recognized by native model admission. Other artifacts remain
unsupported. This route adds no minimum ADA premise and prints no accepted
transaction witness. A PASS establishes existence within the selected model and
bound, without establishing deployed-ledger reachability or funds safety. See
the [UP-000 scope](../../Formal/Properties/Universal/UP000/README.md).

UP-001 checks nonacceptance for undeclared purposes within **5,000,000 CEK steps**.
A selected combination for an already declared purpose has no obligations and
returns INCONCLUSIVE with an explanation. Fuel exhaustion satisfies this bounded
claim; it does not establish explicit rejection. Current adapters support
absent/empty parameters; Input preserves nonempty descriptions without applying
values.

The failing validator and invalid artifact exercise other outcomes:

```sh
plutus-upv run Workflow/Tests/UP001/Inputs/plutus.json vault_buggy.vault_buggy --check UP-001 --timeout-ms 120000
plutus-upv run Workflow/Tests/UP001/Inputs/invalid-code.json invalid.invalid --check UP-001
```

Run UP-004 against the original reference vesting fixture from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-004
```

The Claim and Cancel combinations each ask for a model-valid explicitly rejected
context within **1,000,000 CEK steps**. Rejection means an error or a non-unit halt;
fuel exhaustion does not count. The two primary existential goals,
`someRejected_claim` and `someRejected_cancel`, include validity and rejection,
so these checks need no separate applicability jobs. The expected reference outcome is
two PASS results; inspect the retained results to confirm the actual outcome.

The `Review` path links `UP-004-v1-TxM-007` and `UP-004-v1-TxM-008` folders,
each retaining generated `Types.lean`, `Tx.lean`, and `Checks.lean` plus results
and logs. UP-004 skips the second artifact recognized by native model admission;
unknown artifacts remain unsupported. This route adds no minimum ADA premise
and prints no rejected transaction witness. A PASS establishes existence in the
selected model and bound, without establishing ledger reachability, arbitrary
action coverage, or funds safety. See the
[UP-004 scope](../../Formal/Properties/Universal/UP004/README.md).

Run UP-011 against the original reference vesting fixture from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-011 --timeout-ms 300000
```

This selects one Claim combination, TxM-007, with a main obligation and linked
applicability. It changes only the first continuation's payment credential,
preserving staking, value, and datum. The five premises require baseline validity,
baseline acceptance, rejection after redirection, a different credential, and
changed-context validity. Acceptance and explicit rejection use **1,000,000 CEK
steps**; fuel exhaustion does not establish rejection.

The redirect guard changes matching outputs' addresses and removes their datums.
Its rejection does not independently establish reliance on the address. This
property does not establish the full address rule. Cancel has no continuation
and is not runnable; its earlier expected false applicability remains a
standalone diagnostic.

The reference expectation is one PASS combination, supported by Valid observations
for `continuationElsewhere_claim` and `continuationElsewhere_claim_applies`.
A main observation cannot establish PASS without trustworthy linked applicability.
Inspect the actual results under the printed `Review` path; expectations do not
record a fresh run. The `UP-011-v1-TxM-007` folder retains generated `Types.lean`,
`Tx.lean`, and `Checks.lean`, plus results and execution evidence.

UP-011 admits only the original artifact, skipping the second vesting artifact
recognized by native model admission. Unknown artifacts remain unsupported.
The [UP-011 scope](../../Formal/Properties/Universal/UP011/README.md) records the
fixed model, compiled address-ignoring control, and remaining coverage limits.
These automated scenarios use the app API; the command above checks the public CLI.

Run the experimental vesting profile with:

```sh
plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json linear_vesting.linear_vesting --check UP-012 --timeout-ms 300000
```

UP-012 has three registered combinations: Claim (TxM-007), Cancel (TxM-008),
and key-datum spend (TxM-009). Each contains a property
and linked applicability obligation. They use the **1,000,000-step** bound and
fixed one-signer models. The adapter accepts two exact vesting artifacts: the original
PR #55 fixture and the reviewed vault-demo build using Aiken 1.1.21 with stdlib
3.0.0 for TxM-007/008. TxM-009 uses reusable structural admission for compatible unparameterized V3
spending targets, without adding compiled-artifact allowlist entries. Unsupported artifact/model pairs appear as
SKIPPED in the app, with an unsupported reason. Owner, signer, and recipient vary independently in
TxM-009; passing does not establish correct-owner authorization. Its intended universal meaning remains
separate work in [issue #33](https://github.com/no-witness-labs/contracts-library/issues/33).

Run UP-013 against the original reference vesting fixture from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-013 --timeout-ms 300000
```

The Claim (TxM-007) and Cancel (TxM-008) combinations replace the baseline's
validity range with the fully unbounded range `(-∞, +∞)`. Each requires a
model-valid accepted baseline and a model-valid changed context, then checks
explicit rejection of the change within **1,000,000 CEK steps**. Fuel exhaustion
does not count as rejection. Each main obligation has separate linked
applicability; a main result cannot establish PASS without trustworthy evidence
that its premises have a witness.

The expected reference outcome is two PASS combinations, supported by four Valid
observations. Inspect the actual results and logs under the printed `Review`
path. The `UP-013-v1-TxM-007` and `UP-013-v1-TxM-008` folders retain generated
`Types.lean`, `Tx.lean`, and `Checks.lean` plus results and execution evidence.
These expectations are not a record of a new run.

UP-013 skips the second artifact recognized by native model admission; unknown
artifacts remain unsupported. It concerns one fully unbounded range, not every
range missing a lower bound, and does not require every validator to reject
unbounded ranges. Model validity does not establish ledger reachability or funds
safety. See the [UP-013 scope](../../Formal/Properties/Universal/UP013/README.md)
for the fixed models, original-artifact restriction, and open definition work.

Run UP-014 against the original reference vesting fixture from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-014 --timeout-ms 300000
```

This selects TxM-007 Claim only. The mutation replaces the first continuation's
inline datum with exactly
`Constr 0 [credential1, credential2, List [], Int start, Int end, Int recovery]`.
The two credentials and three integers are symbolic, but the vesting-asset list
is always empty. The baseline datum has one vested asset; the output's address
and value remain unchanged.

The five premises require baseline validity, acceptance within 1,000,000 CEK
steps, explicit rejection after redirection within that bound, a different
replacement datum, and validity after replacement. Under those premises, the
main obligation requires explicit rejection of the replacement. An error or
non-unit halt counts as rejection; fuel exhaustion does not. The separate
applicability obligation requires a witness satisfying all five premises.

The reference expectation is one PASS combination, supported by Valid observations
for `continuationOtherDatum_claim` and `continuationOtherDatum_claim_applies`.
A main observation cannot establish PASS without trustworthy linked applicability.
Inspect actual results under the printed `Review` path; these expectations do not
record a fresh run. The `UP-014-v1-TxM-007` folder retains generated `Types.lean`,
`Tx.lean`, and `Checks.lean`, plus results and execution evidence.

UP-014 skips the second vesting artifact recognized by native admission; unknown
artifacts remain unsupported. Cancel has no continuation and remains a standalone
no-applicability diagnostic. The check does not establish general datum integrity,
nonempty replacement coverage, ledger reachability, or funds safety. The
[UP-014 scope](../../Formal/Properties/Universal/UP014/README.md) explains its fixed
model and compiled control, which checks the continuation payment credential
while ignoring the datum. Automated scenarios use the app API; the command above checks the
public CLI separately.

UP-015 uses the same validator input and native Claim model, TxM-007:

```sh
plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json linear_vesting.linear_vesting --check UP-015 --timeout-ms 300000
```

Its single combination checks acceptance after reversing the two Claim outputs
within 1,000,000 CEK steps. Linked applicability requires a valid accepted original,
a valid reversal, and an output list that changes. The vesting profiles share
the two-artifact allowlist and model preparation. This supplies no general
output-permutation model. See the
[UP-015 scenario](../Tests/UP015/README.md).

The editable [vault-demo project](../Tests/Projects/vault-demo/README.md) combines
the normal vault, buggy vault, and linear vesting in one manually built blueprint.
Its default `aiken build` then `plutus-upv run` path selects all three validators
and all registered combinations. The app and test command do not build Aiken
sources automatically. The original UP-012 regression input remains unchanged;
the reviewed demo build has an independent shared regression snapshot.

The eight scenarios test workflow behavior. They do not establish general
property or model readiness. Definition work remains open in
[UP-000 #22](https://github.com/no-witness-labs/contracts-library/issues/22),
[UP-001 #23](https://github.com/no-witness-labs/contracts-library/issues/23),
[UP-004 #25](https://github.com/no-witness-labs/contracts-library/issues/25),
[UP-011 #32](https://github.com/no-witness-labs/contracts-library/issues/32),
[UP-012 #33](https://github.com/no-witness-labs/contracts-library/issues/33),
[UP-013 #34](https://github.com/no-witness-labs/contracts-library/issues/34),
[UP-014 #35](https://github.com/no-witness-labs/contracts-library/issues/35), and
[UP-015 #36](https://github.com/no-witness-labs/contracts-library/issues/36).
[Model authoring #89](https://github.com/no-witness-labs/contracts-library/issues/89)
and [candidate integration #96](https://github.com/no-witness-labs/contracts-library/issues/96)
remain separate work.

Solver results inherit Blaster's SMT trust boundary. Model validity, ledger
reachability, source correspondence, and protocol relevance remain separate
questions. See [validation history](VALIDATION.md) for earlier measured runs and
the [UP-012 guide](../Tests/UP012/README.md) for its restrictions.

## Test the tool

```sh
plutus-upv test
```

The command builds the test targets and runs all workflow suites with verbose
commands, case starts, stdout/stderr, durations, and evidence paths. It retains
logs and summaries in a fresh ignored `output/test.XXXXXXXX/` directory.

Intentional FAIL and INCONCLUSIVE cases count as successful tests when their
assertions match. The test command returns zero only when all required suites
ran and passed. Independent suites continue after a test failure; a build failure
stops execution so stale binaries cannot produce a false success. The
[test index](../Tests/README.md) lists focused commands and legacy scenario tests.

To exercise reusable TxM-009 admission from `formal/`:

```sh
plutus-upv run Workflow/Tests/UP012/Inputs/reusable.json controller_gate.controller_gate --check UP-012 --timeout-ms 300000
```

Check the snapshot's validator titles if choosing another target. `--check UP-012`
selects the property and scans all three registered model combinations; it does
not select a client model ID. For this target, TxM-007/008 are expected to be
SKIPPED by their exact vesting guards. TxM-009 admits compatible unparameterized
V3 spending schemas and validates compiled code. Structural admission does not
infer who must sign or establish general authorization safety. The new fixtures
passed their scenario tests: signer enforcement produces PASS, omitted enforcement
produces FAIL, and the never-accepting control cannot establish applicability.

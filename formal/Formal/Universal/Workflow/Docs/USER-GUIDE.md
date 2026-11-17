# Run Plutus UPV

Plutus UPV checks compiled validators with Lean and configured proof tools.
The M1.1 prototype accepts the documented Aiken-style Plutus V3 blueprint profile.
It prints per-validator results and retains generated Lean and evidence locally.
Properties and models remain experimental; see the [property bank](../../Properties/README.md)
for each check's meaning and limits. M1.2 specification proofs run separately.

## Prepare once

Have Lean **4.24.0**, Z3 **4.15.2**, GNU coreutils (`timeout`, `mktemp`, `date`,
`sha256sum`), and Git on `PATH`. From the repository root:

```sh
./formal/install.sh
```

The installer builds the app and links `~/.local/bin/plutus-upv` to this checkout.
Keep the checkout in place; it supplies code, metadata, and dependencies. The
installer prints any needed PATH command without editing your shell config.
Use `--bin-dir DIRECTORY` for another location. Reinstalling for the same checkout
is safe; an unrelated existing command is not replaced.

From `formal/`, `./plutus-upv ...` and `lake exe plutus-upv ...` also work.
The shell launcher resolves input/selection-file paths from the calling directory.
The first build may download dependencies; committed `lake-manifest.json` pins
revisions. Reserve `lake update` for intentional upgrades. Runtime checking needs
no AI service, Python, or Nix. The app does not build your Aiken project.

## Run and select work

From your project's directory containing a compiled `plutus.json`:

```sh
plutus-upv run
```

Defaults select all logical validators and registered property/model combinations,
with **5 minutes per combination**. To narrow the work:

```sh
plutus-upv run --validator vault.vault --check UP-001
```

For a repository fixture, run from `formal/`:

```sh
./plutus-upv run Formal/Universal/Workflow/Tests/UP001/Inputs/plutus.json --validator vault.vault --check UP-001 --timeout-ms 120000
```

The earlier positional validator form also works. Repeat `--validator` and
`--check` to select several. Validator names may be full `module.validator` names
or unambiguous short names. Multiple handler entries form one logical target.
Selection preserves declaration order and runs each combination once.

Malformed compiled code becomes a validator preparation error while other
validators continue. Invalid shared JSON/title structure stops discovery.
Current adapters accept absent/empty parameter lists; they do not apply nonempty
parameters. Standalone CBOR and function targets need separate intake support.

## Select properties with a file

Copy [checks.example.json](../../checks.example.json) or write a flat boolean map.
For example, this file enables only UP-001; omitted IDs stay off:

```json
{
  "UP-001": true
}
```

```sh
plutus-upv run --checks-file checks.json
```

With no file or `--check`, every registered property runs. A file enables only
explicit `true` entries; each property selects all its registered model pairings.
Clients do not supply transaction models. Unknown IDs, nonboolean values, and
malformed files fail before verification. `--check` and `--checks-file` cannot
be combined. An empty enabled set is a valid no-op that establishes no property.

## Read the terminal and run files

Counts represent property/version/model combinations, not individual supporting
obligations. The app supplies a key below its table and no overall verification
verdict.

| Terminal category | Meaning |
| --- | --- |
| PASS | Met the check's expectations within its model, assumptions, and bounds |
| FAIL | A qualified observation did not meet the check's expectations; inspect the evidence |
| SKIPPED | No applicable obligations, or an unsupported validator/model pairing |
| ERROR | No reliable result for another reason, including unestablished applicability, invalid plans, or evidence/preparation/storage failure |
| TIMEOUT | Unresolved verification exceeded the executor's limit |

Operational errors take precedence over timeout hints. Saved assessments use
PASS/FAIL/INCONCLUSIVE; typed `not_run` reasons and guarded `timed_out` flags in
the run index distinguish terminal categories. The app does not infer them by
parsing reason text.

Open the printed **Review** path (`README.md`) to browse results and generated
Lean. **Index** points to `run.json`. Each invocation creates a separate ignored
directory under this app checkout's `formal/output/`, leaving prior runs intact:

```text
output/run.<timestamp>.<unique-id>/
├── README.md, run.json
├── discovery.json
├── input.json
├── checks.json                         # when supplied
├── sources/                            # captured project imports, compiled files, logs, environment records
└── validators/<validator>/<property>-v<version>-<model>/
    ├── check-result.json, input.json, execution.json
    └── Generated/
        ├── Types.lean, Checks.lean
        ├── Tx.lean                     # when the generator emits a model alias
        └── compiler outputs and logs
```

| Evidence | What to inspect |
| --- | --- |
| `run.json` | Options, planned work, result paths, errors, elapsed time, completion marker |
| Root `input.json`, optional `checks.json` | Exact captured input and selection bytes |
| `check-result.json` | Assessed identity, target, status, obligations, reasons, and evidence |
| `execution.json` | Attempted commands, timing, raw observations, and diagnostics |
| `Generated/` | Actual target/model Lean submitted for verification and its logs |
| `sources/index.json` | Imported project source/compiled hashes, imports, compilation state, and tool/dependency identities |

File availability depends on progress. Unreadable input has no snapshot;
validator preparation errors produce no generated proof files. An interrupted
run may leave its last saved index unfinished. Filesystem names encode special
characters; the index retains canonical validator names.

Preparation diagnostics also remain under `output/discovery.*/`. A selected
source that fails compilation exits with code `2` and prints that evidence path;
explicitly selected checks avoid unrelated broken sources.

Generated checks use captured transitive project imports compiled once per run
as needed. External libraries still use the installed environment. The output
records pins, actual revisions, and tracked dirty state, but excludes dependency
sources and runtime; independent replay remains future work. See the
[developer file map](DEVELOPER-GUIDE.md#generated-goals-and-supporting-files).
The navigation README is not the separately planned final [client report](https://github.com/no-witness-labs/contracts-library/issues/83).
The app does not generate the legacy report.json/report.txt files.

## Time limits and exit codes

`--timeout-ms 120000` gives each selected combination 120 seconds across its
generated modules; the default is 300000 milliseconds. Launcher and supporting-source
preparation have separate budgets of at least thirty seconds, otherwise the
selected timeout. Setup and retention add overhead. Wall-clock limits are distinct
from the property's CEK-step bound.

Independent checks continue after ordinary FAIL, INCONCLUSIVE, or timeout outcomes.
A shared source-capture/compilation failure retains available files and diagnostics,
records INCONCLUSIVE, and counts as an app error. Later generated checks in that
source session do not execute; their available files and explanations remain.
Start a new run after correcting the source problem.

| Product exit | Meaning |
| --- | --- |
| `0` | Orchestration and retention completed, including ordinary FAIL/INCONCLUSIVE results |
| `2` | Input, preparation, catalogue, app, or storage errors prevented normal completion |

A zero exit does not assert property PASS. Inspect both the terminal and saved
results. The older `universal` entry point is retired.

## Property scope and examples

Use the [property bank](../../Properties/README.md) to choose checks and follow
their guides for exact statements, supported artifacts/models, fuel, controls,
and recorded validation. A PASS is scoped to that pairing. A FAIL may refute an
experimental claim without establishing a vulnerability. Model validity does not
prove ledger reachability, source correspondence, or protocol relevance; Blaster
SMT trust and dependency limits remain.

Repository examples from `formal/`:

```sh
# Deliberately failing undeclared-purpose control
./plutus-upv run Formal/Universal/Workflow/Tests/UP001/Inputs/plutus.json vault_buggy.vault_buggy --check UP-001 --timeout-ms 120000

# Invalid compiled input
./plutus-upv run Formal/Universal/Workflow/Tests/UP001/Inputs/invalid-code.json invalid.invalid --check UP-001

# Original vesting artifact: expected qualified FAIL for this experimental rule
./plutus-upv run Formal/Universal/Workflow/Tests/UP012/Inputs/plutus.json --check UP-008 --timeout-ms 300000

# Reusable structural admission; other unsupported model pairings are skipped
./plutus-upv run Formal/Universal/Workflow/Tests/UP012/Inputs/reusable.json controller_gate.controller_gate --check UP-012 --timeout-ms 300000
```

Structural admission does not infer who must sign or establish general
authorization safety. See [UP-012](../../Properties/UP012/README.md) and
[UP-008](../../Properties/UP008/README.md) for those example limitations.
[Migration validation](../../../../MIGRATION.md#validation-record) records the
checked layout/CLI snapshot; examples here do not claim a new solver run.

## Test the tool

```sh
plutus-upv test
```

The command builds all maintained test targets, then runs suites with verbose
commands, stdout/stderr, durations, and evidence paths. Logs and summaries go to
a fresh ignored `output/test.XXXXXXXX/` directory. Expected FAIL/INCONCLUSIVE
controls can pass their enclosing test assertions.

The test command returns zero only when all required suites run and pass.
Independent suites continue after a failure; build failure stops execution to
prevent stale-binary success. The [test index](../Tests/README.md) lists focused
commands and explains the exclusion of standalone candidate and M1.2 proof jobs.

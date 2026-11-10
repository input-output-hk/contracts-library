# Vault demo

A small Aiken project for inspecting Plutus UPV's generated Lean files and
execution evidence. All three validators have no script parameters and declare a
spending handler.

| Validator | Behavior | UP-001 result when the five obligations complete |
| --- | --- | --- |
| `vault.vault` | Requires the datum's owner to sign spending; rejects other purposes | Five PASS |
| `vault_buggy.vault_buggy` | Deliberately accepts spending and other purposes | Five FAIL |
| `linear_vesting.linear_vesting` | Linear vesting with Claim and Cancel actions | Five PASS |

UP-001 checks undeclared purposes. These checks do not establish the spending
handler's authorization correctness. The buggy validator is a negative control
for the workflow.

## Build and run

Use Aiken 1.1.21 and the pinned stdlib 3.0.0 dependency. From this directory:

```sh
aiken build
plutus-upv run
```

Install the app first with [formal/install.sh](../../../../install.sh) if needed.
The app uses this directory's newly built `plutus.json`. Each check uses the
five-minute default; `--timeout-ms` can override it.
The demo's blueprint, build cache, and optional generated artifacts stay ignored
by Git. No automatic Aiken build is added to the app or aggregate workflow tests.

The default command selects all three validators and all fourteen registered
property/model combinations. The expected terminal counts, when every supported
check finishes conclusively, are:

| Validator | PASS | FAIL | SKIPPED | ERROR | TIMEOUT |
| --- | --- | --- | --- | --- | --- |
| `vault.vault` | 6 | 0 | 8 | 0 | 0 |
| `vault_buggy.vault_buggy` | 0 | 6 | 8 | 0 | 0 |
| `linear_vesting.linear_vesting` | 8 | 0 | 6 | 0 | 0 |

These are expected counts for 42 selected combinations, pending a complete run.
UP-000 and UP-004 each add two SKIPPED combinations per validator. The vault
artifacts are unsupported by their models; property-owned rules skip this second
vesting artifact even though shared native admission recognizes it. Both run only
against the original fixture in `UP012/Inputs/plutus.json`.

The declared spend-purpose UP-001 combination is SKIPPED with a not-applicable reason.
UP-012's two vesting combinations and UP-015's one combination are SKIPPED for the
vaults because their compiled artifacts are outside the vesting allowlist.
TxM-009 adds one UP-012 signer-removal combination for each vault: normal PASS
and buggy FAIL, each qualified by applicability. That combination is SKIPPED
for vesting because its six-field datum is incompatible with TxM-009's one-field datum. The property does not establish correct-owner authorization.

## Inspect the output

Open the terminal's `Review` path (`README.md`) for relative links to generated
Lean, results, logs, and shared sources. `Index` points to `run.json`. Outputs
remain under the app checkout's `formal/output/`, with separate folders for each
invocation.

For each validator, the five undeclared purposes produce five pairs of Lean
files: `Types.lean` embeds the compiled script and its evaluation interface;
`Checks.lean` applies UP-001 to one purpose model. Each pair lives under:

```text
validators/<validator>/UP-001-v1-<TxM-ID>/Generated/
```

The models are TxM-001 (mint), TxM-002 (withdraw), TxM-003 (publish), TxM-004
(vote), and TxM-005 (propose). TxM-006 selects the declared spend purpose and
therefore produces no Lean check. The terminal calls this SKIPPED; the
saved core assessment retains INCONCLUSIVE with a separate nonexecution reason.
The fifteen UP-001 combinations with obligations generate 30 `.lean` files.
The vesting validator's two UP-012 combinations and one UP-015 combination each
add `Types.lean`, `Tx.lean`, and `Checks.lean`, for nine more files.
The two supported TxM-009 vault combinations add three files each.
Expect 45 generated `.lean` files across all three validators when generation succeeds,
plus shared source snapshots, result JSON, execution manifests, input snapshots,
and compiler logs.
A timed-out check keeps its generated sources and displays TIMEOUT when no
operational error takes precedence. The saved core status remains INCONCLUSIVE.

UP-001 imports its models directly; the vesting combinations use `Tx.lean` aliases
for native TxM-007 (Claim) and TxM-008 (Cancel). The vault UP-012
combinations alias native TxM-009 through their own `Tx.lean`. The app captures and compiles
transitive project imports once
per run under `sources/`; `sources/index.json` records hashes, imports, compilation
state, and environment identities. External compiled libraries still come from
the installed environment, so the folder is not an independent replay bundle.
The properties, native models, and artifact-specific adapters remain distinct.
The vesting adapter recognizes two exact compiled artifacts: the original PR #55
fixture and this reviewed Aiken 1.1.21/stdlib 3.0.0 build. Other compiled code stays
unsupported for TxM-007/008. TxM-009 instead uses reusable structural admission.
Admission does not establish general
readiness of UP-000, UP-001, UP-004, UP-012, UP-015, or their models.

The app's exit code describes completion and retention. A deliberately failing
vault check can therefore appear in a completed run with exit code 0; inspect
the individual results and logs.

## Provenance and regression fixtures

The two vault validator sources are copied unchanged from the pinned
[UP-001 fixture project](../../UP001/Inputs/), originally attributed to
[PR #47's demo](https://github.com/no-witness-labs/contracts-library/tree/0dde8ae76e3f8a239bf06685f72327aed4a7c3ef/formal/Universal/Demo/aiken).
The source snapshot records Apache-2.0 licensing. This editable project has its
own package name and compiler setting; building it does not update the pinned
fixture's sources, dependency lock, or `plutus.json`.

The vesting source comes from `onchain/` at
`f5cbda7df624f2496dd2e6fe354a0cd15365b923`: `validators/linear_vesting.ak`,
`lib/vesting/linear.ak`, `lib/vesting/types.ak`, and `lib/authorization.ak`.
Only `lib/vesting/linear.ak` has formatting changes; the other three files are
byte-identical to that source revision. The demo keeps Aiken 1.1.21 and stdlib
3.0.0. Its resulting compiled artifact is a second exact supported test artifact.
[Profiles/Inputs/linear-vesting-aiken-1.1.21.json](../../Profiles/Inputs/linear-vesting-aiken-1.1.21.json)
retains an independent regression snapshot. The original
[UP012/Inputs/plutus.json](../../UP012/Inputs/plutus.json) remains unchanged.

# Develop the Plutus UPV workflow

The [overview](../README.md) defines component ownership and terminology; the
[user guide](USER-GUIDE.md) covers CLI operation. This guide connects maintained
definitions and models to generated obligations, metadata, and evidence.

## Definitions, models, and adapters

The [property bank](../../Formal/Properties/README.md) organizes native definitions
and required metadata by category/code. Root/category indexes use checked Lean
names and metadata paths. Each candidate has one primary definition; its file can
also contain applicability predicates, helpers, and lemmas.

The [transaction-model bank](../../Formal/TxModels/README.md) owns native context
constructors and their metadata in individual `Definitions/TxMNNN.lean` modules.
Its index exports metadata as JSON for the reader. Shared model helpers and vesting
types stay at the bank root. Runnable exports use the shared target-purpose type;
native constructors keep their existing ledger input types.

The public [ProductCLI](../App/ProductCLI.lean) delegates run preparation to
[Launcher](../Declarative/Launcher.lean). Lean discovery scans property paths, applies
the shared selection rules, and evaluates
selected property `Run.lean` files, reads their actual model lists, and compiles
only the selected exports. [Declarative/Catalogue.lean](../Declarative/Catalogue.lean)
validates those discovered records and supplies the existing callable core. The
[execution guide](../Declarative/README.md) describes model conventions and limits.

UP-000, UP-001, UP-004, UP-012, and UP-015 own their run declarations beside their definitions.
Each `models` entry names an enabled native model through `ModelUse.id` and retains
that pairing's reviewed `limitations`. This one list controls execution enablement;
authoring a descriptive record does not independently register a check.
Model exports identify native builders, admission requirements, and an optional
fixed purpose using the shared target types. Generic evaluator
helpers live in `Formal/Support/Execution.lean`, without a model-bank aggregate
dependency. `Formal/Support/Compatibility.lean` keeps legacy purpose aliases.

[UP001/Run.lean](../../Formal/Properties/Universal/UP001/Run.lean) owns the rule
that skips declared purposes. The shared generator returns no modules or goals
for those pairs, so they receive no passing verdict. The older
[Legacy comparison catalogue](../Tests/Legacy/Candidates/Catalogue.lean), candidate adapters,
and test profiles remain only for regression comparisons under `Tests/Legacy`.

[UP000/Run.lean](../../Formal/Properties/Universal/UP000/Run.lean) and
[UP004/Run.lean](../../Formal/Properties/Universal/UP004/Run.lean) each own an
artifact restriction: they skip the second vesting artifact recognized by native
model admission. Only the original reference artifact receives UP-000 or UP-004
goals. These property restrictions leave the shared TxM-007/008 allowlist unchanged.

The product app repeats the callable core for exact property/version/model
identities. Legacy providers can still emit several combinations in a plan.
Preserve each definition's actual domain, bounds, and restrictions when adapting it.

## Metadata and schemas

| Record | Authoritative source | Schema/reader |
| --- | --- | --- |
| Property | Each property's `metadata.json` in Formal/Properties | [Record schema](../../Formal/Properties/property-definition.schema.json), [Metadata/Property.lean](../Metadata/Property.lean) |
| Transaction model | Metadata beside its native constructor, exported through the model index | [Model schema](../../Formal/TxModels/transaction-model.schema.json), [Metadata/TxModel.lean](../Metadata/TxModel.lean) |
| Combined check | Property-owned `Run.lean` plus the selected native model; [older bindings](../Tests/Legacy/Candidates/combined-checks.json) serve comparison tests | [Combined-check schema](../Metadata/combined-check.schema.json), [Metadata/TxModel.lean](../Metadata/TxModel.lean) |

The property record groups identity (`id`, `definition_version`, `title`,
`category`), explanation (`summary`, `claim`, `purpose`), scope
(`relevance_conditions`, `preconditions`, `limitations`), formalization
(`primary`, `theorems`), and `references` using label/target pairs.
`schema_version` identifies its metadata format, currently 2; maintained property
definitions use version 1. `primary` identifies the native mathematical statement,
not the source-generation adapter. Static theorem names are not results for the
supplied target; current records have no static target proofs.

Models have exactly four known descriptive fields: `id`, `title`, `plutus_version`,
and `description`. A changed model gets a new TxM ID, keeping existing meanings
stable. Construction facts belong in the description. The Plutus version describes
the context format; execution semantics also depend on the configured proof tools.

A combined check contains `property: {id, definition_version}`, `tx_model`, and
`limitations`. Its public-run limitations come from the selected entry in the
property's `Run.lean`, preserving the reviewed assumptions and caveats of that
pairing. Property scope and model descriptions remain distinct sources of context.
One model may serve several properties, and one property may use several models
through distinct combinations.

Schemas and readers check known fields and types, preserving omitted fields,
explicit empty strings, and empty lists. They reject wrong types, nulls, and
unknown keys. Individual-field optionality and list-cardinality policy remain
open. Structural validity does not make a record runnable or establish a theorem.

Runtime association resolves the selected property ID/version uniquely against
the discovered run declaration. A supplied primary must match the run's statement
declaration. The combined check must match
the property and registered model ID, and the model's Plutus version must match
the target. Missing, ambiguous, or inconsistent selected bindings fail preparation.
References are informational: the workflow does not fetch, import, or execute them.

The old `Workflow/property-definition.schema.json` collection wrapper is removed.
Validate individual records against the property-bank schema; consumers of arrays
can wrap that record schema with `type: "array"` and `items` referencing its `$id`.
`PropertyDefinition.read`/`parseList` still support collections; `readRecord` reads
one property object. Module path migrations are listed below. The separate legacy
schemas under repository `docs/property-catalogue/` remain unchanged; issue #66
tracks their wider migration and other branches.

## Generated goals and supporting files

| Property/model application | Native definition/model |
| --- | --- |
| UP-000 Claim acceptance | [UP000 statement](../../Formal/Properties/Universal/UP000/Definition.lean), [TxM-007](../../Formal/TxModels/Definitions/TxM007.lean) |
| UP-000 Cancel acceptance | The same UP000 statement, [TxM-008](../../Formal/TxModels/Definitions/TxM008.lean) |
| UP-001 mint | [UP001 statement](../../Formal/Properties/Universal/UP001/Definition.lean), [TxM-001 / EveryMint](../../Formal/TxModels/Definitions/TxM001.lean) |
| UP-001 withdraw | [TxM-002 / EveryWithdraw](../../Formal/TxModels/Definitions/TxM002.lean) |
| UP-001 publish/certify | [TxM-003 / EveryPublish](../../Formal/TxModels/Definitions/TxM003.lean) |
| UP-001 vote | [TxM-004 / EveryVote](../../Formal/TxModels/Definitions/TxM004.lean) |
| UP-001 propose | [TxM-005 / EveryPropose](../../Formal/TxModels/Definitions/TxM005.lean) |
| UP-001 spend, when undeclared | [TxM-006 / EverySpend](../../Formal/TxModels/Definitions/TxM006.lean) |
| UP-004 Claim rejection | [UP004 statement](../../Formal/Properties/Universal/UP004/Definition.lean), [TxM-007](../../Formal/TxModels/Definitions/TxM007.lean) |
| UP-004 Cancel rejection | The same UP004 statement, [TxM-008](../../Formal/TxModels/Definitions/TxM008.lean) |
| UP-012 Claim | [Shared UP012 definition](../../Formal/Properties/Universal/UP012/Definition.lean), [TxM-007](../../Formal/TxModels/Definitions/TxM007.lean) |
| UP-012 Cancel | [TxM-008](../../Formal/TxModels/Definitions/TxM008.lean) |
| UP-012 key-datum spend | [TxM-009](../../Formal/TxModels/Definitions/TxM009.lean), [reusable preparation](../Preparation/TxM009.lean) |
| UP-015 Claim output reversal | [UP015 definition](../../Formal/Properties/Universal/UP015/Definition.lean), the same [TxM-007](../../Formal/TxModels/Definitions/TxM007.lean) |

UP-000 applies one existential statement to each native Claim/Cancel family.
The generated `someAccepted_claim` and `someAccepted_cancel` goals each require
a context satisfying `validScriptContext` that the selected program accepts
within 1,000,000 CEK steps. Each combination has one primary goal and no separate
applicability goal. The original `Workflow/Tests/UP012/Inputs/plutus.json` artifact
is the only admitted UP-000 target. It adds neither a minimum ADA premise nor
a printed accepted-transaction witness. An established model witness does not
establish deployed-ledger reachability or funds safety.

UP-004 applies an existential rejection statement to the same Claim/Cancel
families and original artifact. `someRejected_claim` and `someRejected_cancel`
each require a context satisfying `validScriptContext` that the selected program
rejects within 1,000,000 CEK steps. Rejection requires an error or non-unit halt;
fuel exhaustion never counts. Each primary goal includes validity and rejection
of the same witness, with no separate applicability goal. The script credential
remains symbolic; neither model ties it to the supplied program's hash.
The route adds no minimum ADA premise or printed witness and does not establish
full ledger reachability, arbitrary action coverage, or funds safety.

Every* models expose full `TxInfo` and purpose fields; the theorem supplies a raw
redeemer. [Common.mkCtx](../../Formal/TxModels/Common.lean) assembles the context.
UP-001 selects only purposes absent from the target's declared handlers, applying
acceptance within 5,000,000 steps. The registry contains all six purpose models;
selecting a declared-purpose model produces an empty attempt with an explanation
and appears as SKIPPED in the product app. It adds no ledger-validity premise.

UP-012 applies one primary statement and a supporting applicability predicate to
Claim, Cancel, and key-datum spend. Each of the three combinations has a property
and linked applicability obligation, for six obligations across all three. Baseline models have one signer;
the property removes it to construct a second context outside that baseline family.
Its `validScriptContext` conditions are explicit premises, not guarantees of the
constructor or evidence of ledger reachability. The native model admission accepts two exact
unparameterized vesting artifacts: the original PR #55 fixture and the reviewed
vault-demo build using Aiken 1.1.21 with stdlib 3.0.0. Unknown compiled code remains
unsupported for those models. TxM-009 declares its spending-input requirements
in its native `runnable` export, using shared structural admission and program
preparation. Owner, signer, and recipient remain independent. The public path uses
the same validity predicate and 1,000,000-step bound. Legacy test/profile adapters
retain their earlier comparison APIs; the product does not import those profiles.

UP-015 reuses that exact artifact from `Workflow/Tests/UP012/Inputs/plutus.json`
and the same native Claim constructor. Its primary proposition preserves bounded
acceptance after output reversal. Applicability also requires the output list to
change, excluding identity-mutation witnesses. The two-output model makes reversal
a swap. The model-owned artifact allowlist and shared program preparation provide
the public execution path. They supply no general model authoring or broader
validator support.

UP-012 and UP-015 share the two-artifact allowlist. The reviewed demo build
has an independent snapshot at
`Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json`; the original
UP-012 input remains unchanged. The shared adapter emits the correct script hash
for each recognized artifact. This artifact-specific preparation is distinct from
the generic native property definitions and the fixed native transaction models.
It changes neither their claims nor their bounds and supplies no generic adapter.
The editable source project remains manual; workflow tests do not invoke Aiken.

Adapters unfold shared definitions before Blaster, preserving goal polarity and
the expanded formulas. Tests keep kernel-checked equivalences to frozen legacy
formulas. The retain-signer negative control uses independent legacy formulas and
clears official metadata when changing the property proposition.

| Per-check generated file | Contents |
| --- | --- |
| `Generated/Types.lean` | Embedded compiled program, context argument conversion, and bounded acceptance/rejection predicates |
| `Generated/Tx.lean` | Alias for the selected native context constructor |
| `Generated/Checks.lean` | Concrete target/model theorem expressions and tactic calls |

[Formal/Support/Compatibility.lean](../../Formal/Support/Compatibility.lean) retains
current context aliases and evaluation/signatory helpers. UP-012 uses its
`rejectedWithin` predicate and 1,000,000-step `ledgerFuel`; UP-001 supplies literal
5,000,000 to its acceptance predicate. These are distinct rejection meanings.
UP-015 uses the same 1,000,000-step allowance for acceptance. Its test-only negative
control substitutes rejection after the swap while preserving validator, model,
premises, and applicability. The control clears official property/binding metadata
and is not registered as a candidate.

Pinned dependencies are identified by [lake-manifest.json](../../lake-manifest.json).
Local sources under `.lake/packages/` include `CardanoLedgerApi/V3/Contexts.lean`,
`CardanoLedgerApi/IsData/Class.lean`, `PlutusCore/UPLC/CekMachine.lean`, and
`Blaster/Command/Tactic.lean`. Dependency versions and historical measured runs
remain in [validation history](VALIDATION.md); they do not establish source/ledger
correspondence beyond the checked model.

## Attribution, applicability, and failure evidence

The app resolves each selected binding before looping over validators and reuses
that configured check. The generation plan, execution observations, and assessed
result preserve exact snapshots. `propertyDefinition` retains the property
record. Each job/row retains `txModelId`, `transactionModel`, `combinedCheck`, and
the submitted `statement`, identified by module/name. Snapshot changes prevent
the affected evidence from supporting a conclusive result; raw observations remain.
The theorem expression depends on imported native definitions. The app records
its captured project import closure separately in `sources/index.json`; the
statement alone is not a complete source/dependency fingerprint.

An applicability obligation has the same model/combination as its explicitly
linked property job. Assessor checks the exact module/name link, role, expected
Valid result, and snapshot agreement. Successful applicability qualifies only the
property's own observation. Falsified or unavailable applicability leaves the
linked property INCONCLUSIVE. Independent trustworthy failures retain precedence;
untrusted or incomplete module evidence cannot establish a passing property.

Direct legacy providers can remain explicitly metadata-free; the single-check
core requires the exact configured binding. A preparation error belongs to the
validator's run-index entry because no prepared target exists for a CheckResult.
Catalogue/load errors belong to the selected check entry. Generation/execution
failures after preparation preserve the selected identity in an INCONCLUSIVE
CheckResult when storage permits. The coordinator retains readable failed input,
selection snapshots, effective arguments, and available execution files. See the
user guide for `run.json`, `input.json`, and command details in `execution.json`.

Generated output remains local. Tests that use fixed validators/models are evidence
of those bounded scenarios; their fixtures are not client onboarding requirements.
UP-000, UP-001, UP-004, UP-012, UP-015, and their models remain experimental; these tests do not
establish general readiness. Definition work stays in issues #22, #23, #25, #33, and #36;
general model authoring and candidate integration stay in #89 and #96.

## Module paths and validation

The public app uses the core modules below. Legacy driver and formatter modules
are test fixtures under `Workflow.Tests.Legacy`; their status/row types still
alias Assessor for independent comparisons.

| Former import | Current import |
| --- | --- |
| `Workflow.ProductCLI` | `Workflow.App.ProductCLI` |
| `Workflow.Types` | `Workflow.Types.Target` |
| `Workflow.Jobs` | `Workflow.Types.Jobs` |
| `Workflow.PropertyDefinition` | `Workflow.Metadata.Property` |
| `Workflow.ModelMetadata` | `Workflow.Metadata.TxModel` |

Public component imports and `import Workflow` remain available. The public
executable is `plutus-upv`; comparisons use the internal `workflow_legacy_fixture`
target. The old `universal` executable is retired. Imports in other branches
must follow this table when integrating the cleanup.

Use component tests while changing their contracts, then run `./plutus-upv test`
from `formal/`. The [test index](../Tests/README.md) lists focused commands and
intentional negative controls. A fresh build must succeed before running test
executables. New properties/models need an implemented registered binding and
appropriate applicability/integrity tests; adding metadata alone cannot run a check.

## Callable single-check API

Import `Workflow.App.Verification` for separately callable preparation and one-check
verification. Supply the catalogue prepared from selected property-owned run
declarations. Preparation returns the source snapshot and an intake result. A
configured engine holds operational settings once; `verifyOne` takes the prepared
validator and configured check as its two logical inputs.

```lean
import Workflow.App.Verification
import Workflow.Declarative.Catalogue

open Workflow

def verifyMint (catalogue : Declarative.Catalogue) (leanPath : String) :
    IO Assessor.CheckResult := do
  let preparation ← Verification.prepare "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
  let prepared ← IO.ofExcept (preparation.result.mapError toString)
  let check ← IO.ofExcept (catalogue.loadCheck {
    propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-001" })
  let engine : Verification.Engine := {
    options := { leanPath, budgetMs := 120000, outputRoot := some "output" } }
  engine.verifyOne prepared check
```

The caller prepares the Lean dependency search path as it does for Executor.
`Executor.Options.prepareImports` optionally prepares imports after generated
source retention and returns the search path to use before the proof budget
starts. The app supplies its shared source session through this operational
callback; `verifyOne` still takes only the prepared validator and configured check.
Timeout, tool commands, and output location are engine configuration, distinct
from the CEK bound inside the registered property/model binding. Metadata belongs
to the configured combo and is retained with the result.

The catalogue resolves only the exact registered property/version/model. A new
JSON record cannot add executable code. Single-model adapters generate only the
chosen obligations: one existential goal for UP-000 or UP-004, one undeclared
purpose for UP-001, or one UP-012/UP-015 main/applicability pair.
The core rejects mixed bindings, support-only plans, orphan applicability,
and empty plans containing executable modules. Registered generators remain trusted
code; metadata checks alone cannot inspect arbitrary Lean semantics. Tests check
the exact selected theorem set across generated sources.

Each call uses the captured validator source without rereading and returns the
[Assessor's six-field CheckResult](../Assessor/README.md). It prints nothing.
An attempt retains `input.json`, `check-result.json`, and execution files when
available in its own directory. Unsupported or empty attempts keep the selected
combination and explanation; empty means INCONCLUSIVE. Preparation failure stays
an intake result because there is no prepared validator to verify.

The result references files found during retention and exposes the prepared-input
path only after a successful write. If creating/saving evidence fails, the returned
result is INCONCLUSIVE with reasons. `Executor.Options.directory` lets a configured
engine reserve one fresh check workspace. The engine rejects an existing
directory; Executor receives that reserved empty workspace. With this option,
the core retains raw files in the same place even when Executor cannot save its
manifest. The app also records the missing/invalid manifest as a retention error.

The executor explicitly flushes source, log, and manifest writes and records
`retention_errors` in a retained manifest. The app treats these as operational
errors while keeping the assessed result and its link available.

Without an explicit directory, the older fallback limitation remains: a manifest
write error can leave the Executor's raw directory without a link from the core's
separate incomplete attempt. Neither path promises recovery from every filesystem
failure.

## Callable application orchestration

Import `Workflow.App.Run` to call
`App.Run.runWith registry load request options`. The arguments supply registered
`Workflow.CheckId` identities, their exact resolver, a `Workflow.App.Request`, and
app/executor settings. The result is an `App.RunRecord`; the caller can render its
terminal `text` and inspect `exitCode`. `App.Run.run` adds argument parsing and
terminal printing for the product executable.

The app reads the blueprint once, uses `Input.discover` to enumerate logical
validator groups, and prepares each selected validator once from that snapshot.
`App.Selection` owns CLI and JSON-switch selection. Defaults choose all logical
validators and all fourteen registered combinations (two UP-000, six UP-001,
two UP-004, three UP-012, and one UP-015). Repeat `--validator` or
`--check` to narrow them, or use `--checks-file` with a flat property-ID/boolean
object. With a file, only explicit `true` entries run. Unknown IDs and nonboolean
values are errors; property flags and a file cannot be combined. An empty enabled
set is a valid no-op and establishes no property.

Each combination receives its own operational time limit and workspace. The app
continues independent checks after FAIL, INCONCLUSIVE, or a validator preparation
error. It preserves the existing core assessment policy, six-field CheckResult,
native definitions, and CEK bounds. The terminal counts combinations rather than
supporting obligations and has no overall verification verdict.

The terminal groups results as PASS, FAIL, SKIPPED, ERROR, and TIMEOUT, with a key
below its table. The coordinator supplies typed `CheckResult.notRun` metadata for
validated empty plans or unsupported generation, and `timedOut` from the
executor's recorded state. Both non-execution reasons display as SKIPPED.
Unresolved executor timeouts display as TIMEOUT; other unresolved cases display
as ERROR. A qualified PASS/FAIL retains its verdict, while operational and
validator-preparation errors take precedence over all display hints.
This internal metadata does not alter the six-field check-result JSON or the
assessor's three verdicts. Each run-index check entry retains guarded `not_run`
and `timed_out` fields. Retention failures clear the hints. Source-preparation
failures remain operational ERROR cases; TIMEOUT describes the proof executor.

`App.Output` stores a checkpointed `run.json` in a fresh
`output/run.<timestamp>.<unique-id>/` folder. `App.Review` refreshes a root
`README.md` at each checkpoint with relative links to retained generated Lean,
results, logs, and shared sources. The terminal prints both `Review` and `Index`
paths. Root input/config snapshots accompany validator/check folders containing
results, generated modules, and raw files.

The index retains canonical names, planned identities, run-relative result paths,
and errors. The app safely encodes names into filesystem components. Existing
CheckResults preserve their actual evidence paths. The app checks that each saved
result matches the returned assessment before linking it from the index.

`App.Sources` captures the transitive project imports of generated modules under
one shared `sources/` directory. It compiles each captured module once per run
as needed, checks saved source/compiled hashes before reuse, and puts that
directory first in `LEAN_PATH` for generated checks. `sources/index.json` records
source hashes, imports, compilation state, and external import names. It also
records Lean version output, copied toolchain/Lake configuration and hashes,
and configured dependency pins alongside actual checkout revisions and
`tracked_dirty` state. Source compilation commands, results, stdout, and stderr
live under `sources/_logs/`.

Source compilation has a separate budget of `max(timeoutMs, 30000)` for each
preparation call; the check's generated-module proof budget remains unchanged.
A source capture or compilation failure leaves available generated sources and
source diagnostics, produces an INCONCLUSIVE check, and adds an app operational
error. External compiled libraries still come from the prepared environment.
Dependency sources and the runtime remain outside the bundle; independent
replay remains deferred.

`finished` records completion of orchestration, separately from proof outcomes.
An interrupted run can leave the last successfully saved index unfinished.
Product exit `0` means normal app completion/retention, including ordinary FAIL
or INCONCLUSIVE results. Input, preparation, catalogue, app, or storage errors use
exit `2`. The former `universal` client command is retired. Independent provider and report
comparisons live in `Workflow/Tests/Legacy`; their internal fixture driver is
used by workflow tests.

The app owns terminal presentation independently of final reporting. The separate
human-friendly report consumes retained results in future
[issue #83](https://github.com/no-witness-labs/contracts-library/issues/83); its
contents and format remain undecided. UP-012's intended universal redesign stays
in [issue #33](https://github.com/no-witness-labs/contracts-library/issues/33).

## Reusable TxM-009 admission

`Formal.TxModels.Requirements` records data encodings separately from descriptive
model metadata. `TxM009.inputs` requires a constructor-zero datum with one bytes
field and an empty constructor-zero redeemer. A developer declares a model's
complete encoding requirements in Lean and supplies its preparation binding.
The current Lean-owned catalogue has fourteen registered combinations, including
the two UP-000 and two UP-004 combinations with property-owned artifact restrictions.

`Workflow.Preparation.Compatibility.check` is pure and conservative. It requires
V3, no parameters, and exactly one declared spending handler; other handlers may
coexist. Its supported schema subset is ANY (`{}`), bytes, constructors with
matching indices and field counts, and singleton `anyOf`. It resolves local
`#/definitions/...` references with `~0`/`~1` escaping, rejects percent-encoded
URI fragments and cycles,
and limits traversal depth to 128. It ignores `title`, `description`, and
`$comment`. Unknown validation keywords, missing inputs, unresolved references,
and ambiguous unions produce an unsupported reason and SKIPPED. Admission never
narrows the transaction model's domain. Field labels do not infer owners or roles.

`Workflow.Preparation.Program.support` validates the whole CBOR and Flat encoding
of the actual compiled program. It computes the Blake2b-224 script hash with V3
tag 3. It canonicalizes lowercase hex; it does not trust the supplied hash or
recognize code through an allowlist. `Workflow.Preparation.TxM009` then emits
aliases to the unchanged native model. The existing property, validity premises,
and fuel remain unchanged. TxM-007/008 and UP-015 retain their exact artifact guards.

A new compiled program can therefore use this binding without an allowlist edit.
The match is structural only: it does not establish security roles, correct-owner
authorization, ledger reachability, or broader property coverage. General parameter
support, full schema translation, and property semantics remain deferred. The pilot is
an implementation checkpoint for #96 linked to #88, not a complete typed generator.

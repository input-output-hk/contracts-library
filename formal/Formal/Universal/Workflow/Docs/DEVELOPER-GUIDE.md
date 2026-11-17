# Develop the Plutus UPV workflow

Use this guide for integration APIs, metadata, generated files, and evidence.
The [overview](../README.md) maps components; the [user guide](USER-GUIDE.md)
covers CLI operation; [property-owned execution](../Declarative/README.md)
defines the authoring contract.

## Definitions, models, and adapters

The [property bank](../../Properties/README.md) owns reusable statements,
applicability, metadata, and property tests. The [model bank](../../TxModels/README.md)
owns context constructors, encodings, and admission requirements. Each property's
Run declaration selects models and records the limitations of each pairing.
One property may use several models, and one model may serve several properties.

[ProductCLI](../App/ProductCLI.lean) delegates selected-source preparation to
[Launcher](../Declarative/Launcher.lean). [Catalogue](../Declarative/Catalogue.lean)
validates the discovered property/model records and supplies configured checks
to the core. The [shared generator](../Declarative/Generator.lean) applies the
selected definition to evaluator arguments and the model's context builder.

Model admission and property exclusions are distinct. Admission checks whether
the target fits the model's requirements; a property may then skip an admitted
artifact outside its reviewed scope. Skips emit no obligations or passing verdict.
Read the property guide for its actual formula, domain, CEK bound, and controls.
Preserve those semantics when adapting a definition. Legacy providers and profiles
remain [comparison fixtures](../Tests/Legacy/README.md), not product onboarding requirements.

## Metadata and schemas

| Record | Authoritative source | Schema and reader |
| --- | --- | --- |
| Property | Adjacent `metadata.json` | [Property schema](../../Properties/property-definition.schema.json), [Property reader](../Metadata/Property.lean) |
| Model | Metadata beside its constructor | [Model schema](../../TxModels/transaction-model.schema.json), [Model reader](../Metadata/TxModel.lean) |
| Combined check | Property Run entry plus selected model | [Combined-check schema](../Metadata/combined-check.schema.json), [Binding reader](../Metadata/TxModel.lean) |

Property records group identity, explanation, scope, formalization, and references.
`schema_version` identifies the record format; `definition_version` identifies the
property definition. `primary` names the mathematical statement, not an adapter.
Static theorem references are not proof results for the supplied target.

Model descriptions use four fields: `id`, `title`, `plutus_version`, and
`description`. A changed model receives a new numbered ID. Plutus version
identifies the context format; it does not specify the entire proof environment.
Encoding requirements live separately in native Lean declarations.

A combined check contains `property: {id, definition_version}`, `tx_model`, and
`limitations`. The selected Run entry supplies the pairing limits. These are
distinct from the property's general scope and the model's construction facts.

Readers reject wrong types, nulls, and unknown keys, while preserving omitted
fields, empty strings, and lists. Individual-field optionality and list-cardinality
policy remain open. See the banks for the full field contracts and [#66](https://github.com/no-witness-labs/contracts-library/issues/66)
for wider adoption. Collection consumers can wrap the property-record schema
with array `items`; the Lean reader also retains collection support.

Runtime association requires a unique property ID/version, a matching primary
statement, consistent model identity, and matching Plutus version. Missing,
ambiguous, or inconsistent selected bindings fail preparation. References are
informational: the app does not fetch, import, or execute them. Repository
`docs/property-catalogue/` schemas remain separate legacy formats.

## Generated goals and supporting files

Each executed check retains generated sources under its `Generated/` directory:

| File | Role |
| --- | --- |
| `Types.lean` | Actual compiled program, computed script hash, context encoding, and bounded evaluator predicates |
| `Tx.lean`, when emitted | Alias for the selected native context constructor |
| `Checks.lean` | Concrete theorem expressions and Blaster calls |

A generated module records what is submitted, while imported definitions give
that expression its meaning. The app captures transitive project imports under
one run-level `sources/` directory and compiles each as needed. Generated checks
use those captured modules first in `LEAN_PATH`. Saved source/compiled hashes
are checked before reuse.

`sources/index.json` records imports, hashes, compilation state, external module
names, toolchain/configuration records, configured dependency pins, actual checkout
revisions, and tracked dirty state. Compilation commands/logs live in
`sources/_logs/`. External dependency sources and the runtime remain outside the
bundle; retained output does not yet support independent replay.

The [user file map](USER-GUIDE.md#read-the-terminal-and-run-files) covers input
snapshots, per-check results, execution manifests, and partial runs. Individual
property guides own generated goal names, formula examples, and artifact restrictions.

## Attribution, applicability, and failure evidence

Each job/observation/assessment retains its module/name identity, submitted
statement, role, expectation, model ID, and binding snapshots. The plan also
retains the property record. Snapshot disagreement prevents affected evidence
from supporting a conclusive result; raw observations remain available.

A guarded property links its own applicability job by exact module/name.
Assessor checks the link, role, expected Valid result, and binding agreement.
Only trustworthy linked applicability qualifies the main observation. Falsified,
missing, or unestablished applicability leaves that property INCONCLUSIVE.
Independent trustworthy failures retain precedence; incomplete or untrusted
evidence cannot establish PASS.

Validator preparation errors belong to the validator entry because no prepared
target exists. Catalogue/load errors belong to the selected check entry.
Generation/execution failures preserve the configured identity and INCONCLUSIVE
result when storage permits. Operational errors and missing evidence must never
appear as SKIPPED merely because execution did not finish.

Test controls that substitute a program or proposition use a distinct test
identity and clear official property/binding metadata. Retain actual executed
bytes/input separately from any reference-only fixture. A regression suite may
pass by observing a qualified property FAIL; that does not make the property PASS.

## Module paths and validation

Public imports use `Formal.Universal.Workflow` and its component modules.
The [migration map](../../../../MIGRATION.md#source-map) lists former names.
M1.1 owns the app/property/model tests; M1.2 has its separate
[milestone suite](../../../LinearVesting/Tests/README.md). Shared process helpers
live in `Formal.Shared`. The workspace and public commands stay at `formal/`.

Run affected component/property tests when changing their contracts; the
[test index](../Tests/README.md) lists targets. `./plutus-upv test` builds the
maintained executables before running them, so stale binaries cannot hide build
failures. It does not run every retained standalone or validator-milestone proof.

Record exact code, input bytes, dependency revisions, bounds, and observations.
The [migration record](../../../../MIGRATION.md#validation-record) and
[older validation history](VALIDATION.md) describe the checks performed.
Fixtures establish bounded scenario coverage, not general property readiness,
ledger reachability, source correspondence, or deployment safety. Blaster's SMT
trust and dependency warnings remain part of the evidence boundary.

## Callable single-check API

[Verification](../App/Verification.lean) separates input preparation from one-check
execution. Configure operational options once; `verifyOne` takes a prepared
validator and configured property/version/model combination.

```lean
import Formal.Universal.Workflow.App.Verification
import Formal.Universal.Workflow.Declarative.Catalogue

open Formal.Universal.Workflow

def verifyMint (catalogue : Declarative.Catalogue) (leanPath : String) :
    IO Assessor.CheckResult := do
  let preparation ← Verification.prepare "Formal/Universal/Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
  let prepared ← IO.ofExcept (preparation.result.mapError toString)
  let check ← IO.ofExcept (catalogue.loadCheck {
    propertyId := "UP-001", definitionVersion := 1, modelId := "TxM-001" })
  let engine : Verification.Engine := {
    options := { leanPath, budgetMs := 120000, outputRoot := some "output" } }
  engine.verifyOne prepared check
```

The caller supplies the prepared Lean search path. `Executor.Options.prepareImports`
can retain/prepare shared imports before the generated-module proof budget starts;
the app uses this callback for source capture. Operational timeouts and tool
settings are separate from the check's model, logical premises, and CEK bound.

The core requires a valid binding and jobs attributed to that exact combination.
It validates plan/job snapshots and applicability before accepting results.
Registered generators remain trusted code: metadata checks cannot inspect
arbitrary Lean semantics.
Unsupported or empty plans retain the selected identity and explanation;
empty is INCONCLUSIVE. Preparation failure remains an intake result.

Each attempt retains input, check result, and available execution files. An
explicit `Executor.Options.directory` reserves one fresh workspace; an existing
directory is rejected. The app uses this path to retain raw files even when
Executor cannot save its manifest. Writes are flushed and retention failures
are recorded as operational errors, clearing inconclusive display hints.

Without an explicit directory, a manifest-write failure can leave raw Executor
files unlinked from the core's separate incomplete attempt. Neither path promises
recovery from every filesystem failure. A prepared-input path is exposed only
after its successful write.

## Callable application orchestration

[App.Run.runWith](../App/Run.lean) accepts registered `CheckId` values, their exact
resolver, an `App.Request`, and app/executor options. It returns `App.RunRecord`
with terminal `text`, `exitCode`, and retained run state. `App.Run.run` adds
argument parsing and terminal printing.

The app captures the blueprint once, discovers logical handler groups, and
prepares selected validators once. Each combination has its own workspace and
execution budget. Independent checks continue after ordinary failures or a
validator preparation error. Selection, terminal categories, exit codes, and
file layout are specified in the [user guide](USER-GUIDE.md).

`App.Output` checkpoints `run.json`; `App.Review` updates the navigation README
with relative links to saved results. Canonical names remain in the index while
filesystem components are encoded safely. Saved check results are compared to
returned assessments before the index links them. An interrupted index can
remain unfinished; completion is separate from proof success.

Supporting-source capture/compilation has a separate budget of
`max(timeoutMs, 30000)` per preparation call. Failure retains available sources,
logs, and index records, produces INCONCLUSIVE, and records an app operational
error. Because the source session is shared, later generated checks do not
execute after such a failure; their available files and explanations remain.

The app owns terminal output and local evidence. The separate human-friendly
[report component](https://github.com/no-witness-labs/contracts-library/issues/83)
remains future work.

## Reusable TxM-009 admission

[Requirements](../../TxModels/Requirements.lean) describes model encodings apart
from descriptive metadata. TxM-009 requires a constructor-zero datum with one
bytes field and an empty constructor-zero redeemer. Its
[native export](../../TxModels/Definitions/TxM009.lean) declares those requirements;
[Compatibility.check](../Preparation/Compatibility.lean) performs pure,
conservative schema matching without narrowing the model's domain.

Admission requires V3, no unapplied parameters, and exactly one declared spending
handler; other handlers may coexist. Supported schema forms are ANY (`{}`),
bytes, constructors with matching indices/field counts, and singleton `anyOf`.
Local `#/definitions/...` references support `~0`/`~1` escaping. Percent-encoded
fragments, cycles, unknown validation keywords, missing/unresolved inputs,
ambiguous unions, and traversal beyond depth 128 are unsupported. Descriptive
`title`, `description`, and `$comment` fields are ignored for compatibility.

[Program.support](../Preparation/Program.lean) validates the complete CBOR/Flat
program and computes the V3-tagged Blake2b-224 hash, canonicalizing lowercase
hex rather than trusting a declared hash. [TxM009 preparation](../Preparation/TxM009.lean)
emits native-model aliases. New compatible programs need no code allowlist edit;
other models/properties retain their declared artifact restrictions.

Structural compatibility does not identify required signers or protocol roles,
prove ledger reachability, or establish authorization correctness. General typed
inputs/parameters and model authoring remain [#88](https://github.com/no-witness-labs/contracts-library/issues/88)
and [#89](https://github.com/no-witness-labs/contracts-library/issues/89). Review
[property scope](../../Properties/README.md) independently of preparation success.

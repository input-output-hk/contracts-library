# Property bank

M1.1 properties live directly under `Formal/Universal/Properties/UPxxx/`.
Folder names use Lean module spelling such as `UP001`; metadata keeps `UP-001`
and the `universal` category. Category is metadata, not a directory level.
The intended reuse does not establish that every property applies to every
validator, model, or protocol.

The ten maintained entries each have a primary `Definition.lean`, `metadata.json`,
README, `Run.lean`, and `Tests.lean`. The public CLI discovers their run declarations
without a manual central registration entry.

| Code | Primary claim | Guide |
| --- | --- | --- |
| UP-000 | Existence of a model-valid accepted context within the configured bound | [UP000](UP000/README.md) |
| UP-001 | Nonacceptance over the configured context family | [UP001](UP001/README.md) |
| UP-004 | Existence of a model-valid explicitly rejected context within the configured bound | [UP004](UP004/README.md) |
| UP-007 | Guarded rejection after changing the first continuation's staking credential, with linked applicability; the reference is expected to falsify this rule | [UP007](UP007/README.md) |
| UP-008 | Guarded rejection after adding one unit of a fixed junk asset to the first continuation, with linked applicability; the reference is expected to falsify this rule | [UP008](UP008/README.md) |
| UP-011 | Guarded rejection after changing the first continuation's payment credential, with linked applicability | [UP011](UP011/README.md) |
| UP-012 | Experimental signer-removal rejection with explicit premises | [UP012](UP012/README.md) |
| UP-013 | Experimental fully unbounded-range rejection with linked applicability | [UP013](UP013/README.md) |
| UP-014 | Guarded rejection of an empty-list continuation datum, with linked applicability | [UP014](UP014/README.md) |
| UP-015 | Experimental Claim output-reversal acceptance with nonidentity applicability | [UP015](UP015/README.md) |

```text
Properties/
  README.md
  Common.lean
  Index.lean
  property-definition.schema.json
  UPxxx/{Definition.lean, Run.lean, metadata.json, README.md, Tests.lean}
  UPxxx/Tests/Standalone/  # retained candidate checks, controls, and fixtures
```

[Index.lean](Index.lean) imports the ten definitions and supplies their code-owned
IDs, versions, checked Lean names, and metadata paths. [Common.lean](Common.lean)
defines that reference type. The index contains no duplicate property statements
and imports no workflow code.

Other candidate folders hold retained tests and fixtures under `Tests/Standalone/`.
Their presence does not register a runnable property or imply that a native
definition or metadata record is ready. Their guides retain the standalone
definition modules, model assumptions, and proof limits.

## Test ownership

Shared context/evaluator mappings and continuation-helper equivalences live in
[Tests/ParitySupport.lean](Tests/ParitySupport.lean). Each property keeps its
own statement and mutation proofs; shared support imports no property definition.

Each property's tests belong with that property. `Tests.lean` exercises formula,
model-list, binding, and admission behavior. `Tests/` holds controls and expected
records; `Tests/Standalone/` preserves earlier direct candidate checks and artifact
fixtures. These groups can use different models and expected outcomes.

The workflow aggregate includes selected property suites. Standalone proof jobs
remain explicit commands and may include expected falsifications or unfinished
proofs. Read their recorded limits before running them. [Workflow tests](../Workflow/Tests/README.md)
check the M1.1 app and engine; the [M1.2 suite](../../LinearVesting/Tests/README.md)
lives beside the linear-vesting specification proofs.

A candidate has one primary property statement. Its definition file can also
contain helpers, applicability predicates, and lemmas. Applying it to a validator
and transaction model produces proof obligations; different models alone do not
create different candidate IDs. Transaction models remain in the [model bank](../TxModels/README.md).

Property-owned run declarations select models and define goal arguments for the
execution engine. Each enabled `ModelUse` contains a model `id` and that pairing's
reviewed `limitations`; this list controls registration. Models expose one native
`runnable` declaration. Indexes remain available for legacy tools and metadata consumers.

The ten registered properties and their models remain experimental workflow
scenarios. Registration, metadata validation, and successful tests do not establish
general property or model readiness. Wider definitions remain tracked in issues
#22, #23, #25, #28, #29, #32, #33, #34, #35, and #36; model authoring and candidate
integration remain in #89 and #96. The CLI can bundle several applications for a
selected property; this bank does not add multi-validator selection or change
the verification-core contract.

## Metadata

Each maintained property definition has one metadata file using the shared
[record schema](property-definition.schema.json). Each file holds its property
record as an object. Individual-field required/optional and list-cardinality
policy remain open; runtime use still requires the registered identity and version.
Tests-only candidate folders do not create placeholder metadata or executable
registrations. Wider definition and metadata adoption remains tracked in #66/#96.

The former workflow collection-schema wrapper is removed. Validate these records
with the shared schema; array consumers can wrap it using `type: "array"` and
an `items` reference to its `$id`. The Lean collection reader remains available.
The old central `Candidates/property-definitions.json` source is replaced by these property files.
Runtime reports retain the selected record and exact submitted theorem expressions.

The `U-*` theory catalogue under `Formal/Universal/Theory` is a separate set of entries.
It is not automatically renamed or migrated to `UP-*`. Issue #66 tracks the
wider cross-branch migration.

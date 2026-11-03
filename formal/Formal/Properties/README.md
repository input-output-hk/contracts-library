# Property bank

Property definitions live here by category and stable code. Each property folder
contains its primary `Definition.lean`, descriptive `metadata.json`, and README.
Folder names use Lean module spelling such as `UP001`; metadata keeps `UP-001`.

```text
Properties/
  README.md
  Common.lean
  Index.lean
  property-definition.schema.json
  Universal/
    README.md
    Index.lean
    UP001/{Definition.lean, metadata.json, README.md}
    UP012/{Definition.lean, metadata.json, README.md}
    UP015/{Definition.lean, metadata.json, README.md}
```

[Index.lean](Index.lean) references category indexes. Each category index imports
its definitions and supplies code-owned IDs, versions, checked Lean names, and
metadata paths. [Common.lean](Common.lean) defines that small reference type.
The index contains no duplicate property statements and imports no workflow code.

A candidate has one clear primary property statement. Its definition file can
also contain helper definitions, applicability predicates, and lemmas. Applying
the property to a validator and transaction model produces proof obligations;
different models alone do not create different candidate IDs. Transaction models
remain in the [model bank](../TxModels/README.md).

The application still owns executable adapters and property/model bindings.
The registered UP-001, UP-012, and UP-015 bindings are experimental workflow
scenarios. Registration and metadata validation do not establish general property
or model readiness. Their wider definitions remain tracked in issues #23, #33,
and #36. Model authoring and candidate integration remain in #89 and #96.
The CLI can currently bundle several applications for a selected property. This
bank does not add multi-validator selection or change the verification-core contract.

## Metadata

Every property folder must contain one metadata file using the shared
[record schema](property-definition.schema.json). Each file holds its property
record as an object. Individual-field required/optional and list-cardinality
policy remain open; runtime use still requires the registered identity and version.

The former workflow collection-schema wrapper is removed. Validate these records
with the shared schema; array consumers can wrap it using `type: "array"` and
an `items` reference to its `$id`. The Lean collection reader remains available.
The old central `Candidates/property-definitions.json` source is replaced by these property files.
Runtime reports retain the selected record and exact submitted theorem expressions.

The legacy `U-*` catalogue under `Formal/Universal` is a separate set of entries.
It is not automatically renamed or migrated to `UP-*`. Issue #66 tracks the
wider cross-branch migration.

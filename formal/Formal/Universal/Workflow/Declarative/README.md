# Property-owned execution

`plutus-upv run` discovers property instructions from `Run.lean`, then prepares
only the selected properties and their enabled native models. The shared
catalogue and generator have no property-specific cases. Descriptive metadata
alone cannot enable executable code.

```text
Property Definition + Run + metadata ─┐
                                     ├─ discovery/selection → model binding
Native context builder + runnable ────┘
  → generated Lean → Executor → Assessor → retained result
```

For CLI use, see the [user guide](../Docs/USER-GUIDE.md). The
[property bank](../../Properties/README.md) owns individual claims, model choices,
bounds, applicability, and controls; the [model bank](../../TxModels/README.md)
describes context constructors and admission policies.

## Authoring contract

| Author action | Authoritative file |
| --- | --- |
| State the property, applicability, helpers, and lemmas | Property `Definition.lean` |
| Select compatible models, pairing limits, goals, and fuel | Property `Run.lean` |
| Describe identity, meaning, scope, and references | Property `metadata.json` |
| Check formulas, bindings, and controls | Property `Tests.lean` and `Tests/` |
| Define a model and its admission requirements | `Formal/Universal/TxModels/Definitions/TxMNNN.lean` |

Property folders sit directly under `Formal/Universal/Properties/UPxxx` and have
adjacent Definition, Run, and metadata files. Discovery derives module/export
names from these paths. Category remains in metadata. Models export one
`runnable` description alongside their constructor and metadata.

[PropertyRun](Types.lean) declares:

| Field | Purpose |
| --- | --- |
| `models` | `ModelUse.id` selects a model; `limitations` records that pairing's reviewed scope |
| `statement` | Checked Lean declaration name and arguments before the context builder |
| `applicability` | Optional supporting goal with the same argument convention |
| `fuel` | Positive CEK-step bound used in `{fuel}` argument placeholders |
| `theoremPrefix`, `theoremSuffix` | Generated obligation names; suffix defaults to the context-builder name |
| `scope` | Shared explanation recorded with the generated jobs |
| `skipReason` | Optional target/model exclusion after model admission |

The current generator applies one primary goal and optional applicability goal
to the selected context builder as the final argument. Both jobs expect Valid.
It links applicability by exact module/name. A skip emits no proof modules or
observations and establishes no passing property.

Adding a compatible existing model changes the property's `models` list; adding
a model supplies a new numbered native export. Authors must review the pairing's
meaning and admission requirements. Keep existing model domains, formulas,
expected outcomes, and fuel stable unless a semantic change is explicitly agreed.
Avoid importing concrete model implementations in Run files: those imports would
be real preparation dependencies even when their models are not selected.

## Discovery and retained evidence

[Discovery](Discovery.lean) scans conventional paths and metadata IDs, applies
CLI selection, then compiles/evaluates selected Run declarations to obtain their
actual model lists. It compiles only those model exports and creates the app
bootstrap under a fresh `output/discovery.*/` directory. It does not parse model
lists from Lean source. Generated checks import the selected Definition and Run,
so both are included in source capture.

Explicit selection avoids unrelated broken sources. A selected declaration that
fails to compile stops preparation with diagnostics and no proof verdict. Default
selection requests all available properties. The launcher preparation deadline
is at least thirty seconds, otherwise the requested check timeout; its process
group is terminated on timeout. Execution budgets remain per combination.

Selection files retain their exact bytes, including line endings. Successful
runs retain `discovery.json`; startup errors retain preparation indexes/logs and
print their evidence path. See the [file map](../Docs/DEVELOPER-GUIDE.md#generated-goals-and-supporting-files)
for generated and captured sources.

## Scope and validation

Current admission supports raw unparameterized V3 contexts, exact pinned spending
artifacts, and conservative unparameterized V3 spending-schema matching. Admission
does not infer protocol intent, owner roles, or ledger reachability. The
[developer guide](../Docs/DEVELOPER-GUIDE.md#reusable-txm-009-admission) describes
structural compatibility; property guides record narrower pairing restrictions.
Other signatures and admission methods may require a reviewed shared extension.

The command uses a source checkout and the prepared Lean/Z3 environment. The
separate legacy blueprint translator has its own tooling requirements.

From `formal/`, focused discovery checks are:

```sh
lake exe workflow_property_discovery_tests
lake exe workflow_public_cli_tests
```

Use the [test index](../Tests/README.md) and property guides for other focused
commands, or `./plutus-upv test` for the maintained aggregate. Record actual
source/dependency revisions and expected negative outcomes. Test success alone
does not establish a property for a supplied validator.

[Migration validation](../../../../MIGRATION.md) records the current layout
checkpoint. [Lean-only validation](LEAN-VALIDATION.md), [earlier validation](VALIDATION.md),
and [integration history](INTEGRATION.md) retain their original revisions and limits;
historical Python-era results do not validate a later implementation or dependency set.

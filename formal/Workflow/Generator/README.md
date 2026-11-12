# Generator component

Generator receives a supplied check provider, a `TargetDescription`, and an
isolated module prefix. It returns a `GenerationPlan` containing Lean sources
and check jobs. It performs no file reads/writes, compiler invocations, or solver
calls.

## Contract

Import `Workflow.Generator` and call:

```lean
Workflow.Generator.generate provider target modulePrefix
```

Generator receives two logical inputs: the validator description from Input,
and a configured check provider. The provider binds the property definition to any
model or harness it needs, together with its expectations and scope. The module
prefix is internal naming information.

The application catalogue can attach a parsed property-definition record to the
provider. Generator preserves that record in the plan without passing metadata
to the proposition-generating function. Descriptions cannot change the emitted
statements or their expectations. See the [metadata contract](../Docs/DEVELOPER-GUIDE.md#metadata-and-schemas).

UP-001 binds its shared definition to generic purpose contexts. UP-011's native
run binds its guarded payment-credential statement and linked applicability to
TxM-007 Claim only, producing two obligations. Its original-artifact restriction
and five premises appear in the
[UP-011 guide](../../Formal/Properties/Universal/UP011/README.md).

UP-014 binds the exact empty-list datum replacement and linked applicability
to TxM-007 Claim on the original artifact. Its two obligations retain all five
standalone guards and the 1,000,000-step bound. See the
[UP-014 guide](../../Formal/Properties/Universal/UP014/README.md) for the replacement
shape, compiled datum-ignoring control, and limits on datum-integrity coverage.

UP-012's test profile applies one shared definition and its applicability predicate to the
Claim/Cancel models, producing four obligations. Native statements and metadata
live in the [property bank](../../Formal/Properties/README.md). UP-015 applies
output-reversal acceptance and nonidentity applicability to the same native Claim
model, producing two obligations. Both vesting scenarios share the pinned artifact
and [test-only preparation](../Tests/Profiles/LinearVesting.lean). Model construction
lives in Formal/TxModels. Blueprint metadata alone does not supply those transaction
shapes; the current profile supplies them explicitly.

A provider supplies property-specific generation through the common interface.
The reusable Generator has no built-in candidate catalogue, validator snapshot,
or transaction model. The application supplies those dependencies.

Each job declares its property ID, name, module, proposition, expected solver
result, and scope. A plan carries the target identity, generated modules, jobs,
and scope notes. A plan without jobs has status `noObligations`; it provides no
passing verdict. Module prefixes must use safe Lean module-name segments.

Provider definitions own their applicability restrictions, model assumptions,
and expected results. Each job declares a property or applicability role. A
property can reference one applicability job by module and name; applicability
jobs expect Valid and have no prerequisite themselves. The provider supplies
these links explicitly, without relying on naming conventions in the engine.

## Candidate composition

The public CLI uses property-owned run declarations through
[App/ProductCLI.lean](../App/ProductCLI.lean) and the
[shared declarative generator](../Declarative/Generator.lean). Each property
selects its compatible models and reviewed pairing limitations.

Independent older providers remain under
[Tests/Legacy/Candidates](../Tests/Legacy/Candidates/) for regression comparison.
They are test fixtures rather than a second public authoring route. The retired
`universal` command is no longer registered.

The agreed direction is to supply reusable models with property definitions and
accept the validator as an input. Definitions have versions and can run with
different models; models have stable numbered TxM IDs, with new IDs for changed
behavior. The catalogue resolves those combinations and reports retain their
snapshots. Legacy generation can bundle combinations; the
[single-check API](../Docs/DEVELOPER-GUIDE.md#callable-single-check-api) selects
one exact property/version/model binding.

The fixed UP-012 and UP-015 vesting profiles supply integration tests. The eight
registered properties and their models remain experimental; these tests do not
establish general readiness. Definition work stays in issues #22, #23, #25, #32,
#33, #34, #35, and #36. Model authoring stays in #89 and wider candidate integration
in #96. Client-specific model
authoring is not a prerequisite of the intended workflow.

## Tests

From `formal/`:

```sh
lake exe workflow_generator_tests
lake exe workflow_generator_integration
```

The first command runs only generic contract checks with stub providers. The
property-owned and workflow scenario suites own their candidate-specific declaration/profile
checks. The second command preserves the Input-to-Generator type-checking check;
it compiles support and proposition definitions without proving them.

The [test index](../Tests/README.md) lists the eight experimental workflow scenarios
and component checks. The [validation history](../Docs/VALIDATION.md) keeps generation,
type-checking, and actual solver observations distinct.

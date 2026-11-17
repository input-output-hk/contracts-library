# Plutus UPV workflow

Plutus UPV checks compiled Plutus validators using Lean and configured proof
tools. The prototype accepts the documented Aiken-style Plutus V3 blueprint
profile and runs all registered validator/check combinations by default.

| Guide | Use |
| --- | --- |
| [User guide](Docs/USER-GUIDE.md) | Install, select checks, read results, and run tests |
| [Developer guide](Docs/DEVELOPER-GUIDE.md) | Use the core APIs and understand metadata and evidence |
| [Property-owned execution](Declarative/README.md) | Author and register properties and models |
| [Property bank](../Properties/README.md) | Find each property's statement, bounds, models, controls, and limitations |
| [Migration validation](../../../MIGRATION.md) | Read the latest layout checkpoint and its evidence limits |
| [Validation history](Docs/VALIDATION.md) | Inspect earlier measured runs |
| [PR #47 reconciliation](Docs/RECONCILIATION.md) | Review legacy behavior and outstanding gaps |

## Milestone ownership

M1.1 owns `Formal/Universal`: this workflow, properties, transaction models,
support, theory, and retained candidate examples. Using a vesting validator as
an example does not make it part of M1.2. The separate
[LinearVesting milestone](../../LinearVesting/README.md) owns its specification
proofs and tests. Both use one Lake workspace at `formal/`; the small
[Shared layer](../../Shared/README.md) holds cross-milestone utilities.

## Components and ownership

```text
Input → Generator → Executor → Assessor → CheckResult
```

The app captures the blueprint once, prepares each selected validator once,
and repeats the core for selected property/version/model combinations.

| Location | Responsibility |
| --- | --- |
| [Input](Input/README.md) | Discover targets, validate interfaces, and decode compiled programs |
| [Generator](Generator/README.md) | Produce Lean modules and declared proof jobs |
| [Executor](Executor/README.md) | Run Lean with deadlines and retain observations and files |
| [Assessor](Assessor/README.md) | Qualify observations and build one check result |
| `App/` | CLI selection, orchestration, run index, and terminal output |
| [Declarative](Declarative/README.md) | Discover property-owned instructions and bind native models |
| `Types/`, `Metadata/`, `Preparation/` | Contracts, record validation, and program/model compatibility |
| [Tests](Tests/README.md) | Component and whole-workflow scenarios, including [legacy comparisons](Tests/Legacy/README.md) |

Properties own their definitions, run declarations, enabled models, and pairing
limitations. The [model bank](../TxModels/README.md) owns context constructors
and admission requirements. Components receive these dependencies explicitly;
they do not import individual candidate implementations. Public imports use
`Formal.Universal.Workflow` and its component modules.

## Supported behavior and limits

The runtime uses Lean and the configured proof tools, with no AI, Python, or Nix
requirement. Input requires embedded compiled code and an explicit Plutus
version. Current adapters accept absent/empty parameters; applying nonempty
parameter lists, standalone CBOR intake, and function targets remain separate work.

The catalogue contains ten experimental properties and twenty pairings over nine
models. Many pairings admit fixed artifacts or transaction shapes. Registration
and successful tests do not establish general applicability. Read the selected
[property guide](../Properties/README.md) before interpreting a result.

Each result concerns a declared formula, model, assumptions, and CEK-step bound.
Bounded nonacceptance and explicit rejection have different meanings; exhaustion
can satisfy the former but never the latter. Model validity does not establish
ledger reachability, source correspondence, protocol relevance, or general safety.
Solver results retain Blaster's SMT trust and the dependencies' recorded limits.

## Core boundary and application outputs

The [single-check API](Docs/DEVELOPER-GUIDE.md#callable-single-check-api) accepts a
prepared validator and one configured combination. Engine options hold operational
timeouts and tool settings separately from the property's logical assumptions.
Linked applicability must be trustworthy before a guarded main observation can
qualify as PASS or FAIL. Missing or incomplete evidence leaves it INCONCLUSIVE.

| Output | Responsibility |
| --- | --- |
| Terminal | Per-validator counts, timing, errors, and output paths; no overall verification verdict |
| Local run files | Inputs, selected bindings, results, generated Lean, logs, captured sources, and navigation/index files |
| Final report | Future human-friendly presentation of retained results, tracked in [#83](https://github.com/no-witness-labs/contracts-library/issues/83) |

Each invocation creates a fresh ignored output directory. Supporting project
sources are captured and compiled once per run as needed; external libraries
still come from the installed environment. The output is not an independent
replay bundle. See [run files](Docs/USER-GUIDE.md#read-the-terminal-and-run-files).

Product exit `0` means orchestration and retention completed, including ordinary
FAIL/INCONCLUSIVE outcomes. Exit `2` indicates input, preparation, catalogue,
app, or storage errors. An empty selection is a no-op and establishes no property.
The retired `universal` executable's report and exit contract survive only in
legacy test fixtures.

## Glossary

| Term | Meaning |
| --- | --- |
| Target | The selected compiled validator and its interface |
| Property | A reusable behavioral statement; candidate definitions remain under review |
| Transaction model | A family of contexts and constructed relationships |
| Combined check / variant | One property-definition version paired with a model and reviewed limitations |
| Check job | One generated obligation, identified by module/name, role, expectation, and binding |
| Applicability | A linked obligation witnessing the guarded property's premises |
| Generation plan | Generated modules, jobs, metadata, and notes |
| Job observation | Attributed solver output before assessment |
| CheckResult | One assessed combination, including obligations, reasons, and evidence |

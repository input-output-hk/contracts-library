# Plutus UPV workflow

Plutus UPV (Universal Property Verifier) checks universal properties against
compiled Plutus validators using ordinary Lean code and configured proof tools.
The prototype supports the documented Aiken-style Plutus V3 blueprint profile.
The app processes all logical validators and all sixteen registered property/model
combinations by default, with optional validator/property filters and a property
switch file. UP-000, UP-004, and UP-013 check the original vesting artifact with Claim and Cancel.
UP-012 supports pinned vesting profiles and reusable TxM-009 preparation; UP-015 uses
the pinned vesting profiles. These six properties and their models support prototype
testing; their broader definitions and coverage still need review.

| Guide | Use |
| --- | --- |
| [User guide](Docs/USER-GUIDE.md) | Prepare the tools, run the CLI, find outputs, and run tests |
| [Developer guide](Docs/DEVELOPER-GUIDE.md) | Understand metadata, bindings, source files, and component integration |
| [Validation history](Docs/VALIDATION.md) | Inspect evidence from earlier checkpoints and its limits |
| [PR #47 reconciliation](Docs/RECONCILIATION.md) | Review retained behavior and outstanding delivery gaps |

## Components and ownership

```text
Input → Generator → Executor → Assessor → CheckResult
```

Input discovers logical validators and validates each selected embedded program. Generator
constructs obligations through a supplied provider. Executor runs Lean under a
shared budget for one combination and retains observations. Assessor qualifies
them into one structured CheckResult. The app repeats the core over selected
validators/combinations, retains run files with a navigation README, and calculates
the terminal summary.
The final human-friendly report remains separate work in
[issue #83](https://github.com/no-witness-labs/contracts-library/issues/83).

| Location | Responsibility |
| --- | --- |
| [Input/](Input/README.md) | Supported artifact intake, decoding, and target descriptions |
| [Generator/](Generator/README.md) | Pure generation of Lean modules and declared check jobs |
| [Executor/](Executor/README.md) | Isolated runs, process deadlines, diagnostics, and evidence |
| [Assessor/](Assessor/README.md) | Expected/observed comparison, applicability, and one-check results |
| [Tests/Legacy/](Tests/Legacy/README.md) | Independent older providers, report fixtures, and their internal test driver |
| `App/` | CLI selection, blueprint orchestration, run files/index, and terminal rendering |
| `Types/` | Shared target/input and generation/job contracts |
| `Metadata/` | Property/model metadata readers and binding validation |
| [Declarative/](Declarative/README.md) | Property-owned discovery, shared model binding, and generation |
| `Preparation/` | Reusable program decoding and model-input compatibility checks |
| [Tests/](Tests/README.md) | Component controls and the UP000/UP001/UP004/UP012/UP013/UP015 workflow scenarios |
| [Formal/Properties](../Formal/Properties/README.md) | Native primary definitions, metadata, and category/code indexes |
| [Formal/TxModels](../Formal/TxModels/README.md) | Native context constructors and their metadata |

Each property owns its run declaration and enabled model entries beside its
definition, metadata, and tests. An entry names a compatible model and retains
the reviewed limitations of that pairing. Native models export their builders
and admission requirements; shared Lean discovery prepares only the selected
properties and models.

The component entry modules and `Workflow.lean` remain public imports.
The components receive explicit inputs and do not import candidate or scenario
implementations. Application composition supplies those dependencies.

## Supported behavior and limits

- Property discovery, model preparation, and execution use Lean code with the
  configured proof tools. The runtime requires no AI services, Python, or Nix.
- Input accepts a blueprint with embedded compiled code and explicit Plutus
  version. It decodes the program before generation. Standalone CBOR and function
  targets need their own input contracts.
- Input preserves parameter descriptions; current adapters accept absent/empty
  parameters and reject unapplied nonempty lists.
- UP-000 asks for a model-valid accepted context within 1,000,000 CEK steps,
  separately for Claim and Cancel. Its binding admits only the original vesting
  artifact; it supplies neither a printed transaction witness nor ledger reachability.
- UP-001 checks nonacceptance for undeclared purposes within 5,000,000 CEK steps.
  Exhaustion satisfies this claim; explicit rejection is a different statement.
- UP-004 asks for a model-valid explicitly rejected context within 1,000,000 CEK
  steps, separately for Claim and Cancel on the original vesting artifact.
  An error or non-unit halt counts as rejection; fuel exhaustion does not.
  Each existential goal includes validity and rejection, with no separate applicability job.
- UP-012 applies the experimental signer-removal definition to the fixed Claim
  and Cancel models and the key-datum spend model. Its applicability obligations qualify the corresponding
  property obligations. It is not a general required-signer audit for new validators.
- **UP-013** replaces the validity range with the fully unbounded range and
  requires explicit rejection within 1,000,000 CEK steps. Claim and Cancel each
  require a model-valid accepted baseline and a model-valid changed context,
  with separate linked applicability. The claim concerns this single range on
  the original vesting artifact; it is not a universal requirement for all validators.
- Within one combination, a qualified, trustworthy FAIL takes precedence. Missing,
  interrupted, or untrusted evidence cannot establish PASS. An empty plan is
  INCONCLUSIVE. The app displays per-validator counts without an overall verdict.
- Solver observations inherit Blaster's SMT trust boundary. Model validity,
  ledger reachability, source correspondence, and protocol relevance are separate
  questions. Clients assess which reported claims matter to their protocol.
- Each app invocation retains results, inputs, generated sources, and raw logs in
  a fresh ignored local output folder, grouped by validator and check. A root
  README links retained files; the run index records incomplete work/errors.
  The app captures and compiles shared imported project sources once per run as
  needed and records dependency identities. External libraries still use the
  installed environment; independent replay remains deferred. Fixed fixtures
  stay committed.

## Core boundary and application outputs

The [callable core](Docs/DEVELOPER-GUIDE.md#callable-single-check-api) separates
validator preparation from verification of one property-definition/model combination
with its linked proof obligations. Engine settings hold operational timeouts and
tool configuration. The app captures the blueprint once, prepares each selected
validator once, and gives every selected combination its own operational timeout.
Individual check or validator preparation failures do not stop independent work.

The three outputs have separate responsibilities:

| Output | Responsibility |
| --- | --- |
| Terminal summary | App-owned counts, timing, useful errors, and output paths |
| Local run files | Navigation README, index, captured inputs/configuration and imported project sources, assessed check results, generated Lean, and logs |
| Final report | Future human-friendly presentation of retained results; contents/format remain undecided |

The product exits `0` when orchestration and retention complete, including ordinary
FAIL/INCONCLUSIVE outcomes, and `2` for input/preparation/catalogue/app/storage
errors. An empty enabled selection is a no-op that establishes no property.
The older bundled providers and report contract are retained only in
[legacy test fixtures](Tests/Legacy/README.md). `plutus-upv` is the public
command; the old `universal` executable is retired.

Additional input formats, typed parameter application, and property-design
improvements remain separate work. Issue #39 tracks the workflow; #33 tracks
UP-012's intended universal design and #66 tracks wider catalogue migration.

## Glossary

| Term | Meaning |
| --- | --- |
| Check target | The subject selected for checking; currently a validator |
| Target description | The compiled artifact and interface metadata passed from Input to Generator |
| Parameter description | Ordered interface metadata for configuration arguments, without applied values |
| Input artifact | The document or serialized program supplying a target; distinct from the target kind |
| Blueprint | A CIP-57 document describing validators and interfaces, with optional compiled content |
| Script CBOR | Serialized compiled Plutus code in a supported input representation |
| Property | A statement about target behavior |
| Candidate property | A proposed property whose definition or intended use remains under review |
| Transaction model | A family of contexts and constructed relationships; one model can serve several properties |
| Combined check / check variant | One property-definition version paired with a model and stated assumptions/limitations |
| Check definition | The property statement, model assumptions, applicability conditions, and expected observations specifying a check |
| Check job | A generated obligation with its expectation, scope, role, and execution identity |
| Applicability obligation | Establishes that the premises needed by a linked property check have a witness in the model |
| Candidate catalogue | References to maintained check implementations and supporting models |
| Run selection | The checks chosen by application defaults or supported explicit controls |
| Workflow test scenario | Candidate/model references, prepared target inputs, and expected outcomes for testing the assembled workflow |
| Check provider | Ordinary Lean generation code implementing the Generator contract |
| Generation plan | Modules, jobs, metadata, and notes for one generation request; currently it can bundle combinations |
| Job observation | An attributed solver result and diagnostics, before comparison with the declared expectation |
| Execution evidence | Retained sources, logs, process details, and observations for an attempt |
| CheckResult | One assessed property/version/model combination, with obligations, scope, reasons, and evidence |
| Terminal summary | The app's end-of-run table and operational details |
| Run files | Local retained inputs, results, generated code, logs, and their index |
| Final report | Human-friendly presentation of retained results, designed separately |

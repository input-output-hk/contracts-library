# PR #47 reconciliation

This document preserves earlier checkpoint evidence. The `universal` user command
is now retired; retained comparison code is under `Workflow/Tests/Legacy`.
Use the current [user guide](USER-GUIDE.md) for supported commands.


This delivery comparison records the referenced checkpoints and remaining gaps.
Its historical source paths may differ from the current
[module map](DEVELOPER-GUIDE.md#module-paths-and-validation). Keep the original
semantic comparisons distinct from later structural cleanup or validation results.

[Issue #39](https://github.com/no-witness-labs/contracts-library/issues/39),
branch `feat/39-developer-workflow`, and
[draft PR #52](https://github.com/no-witness-labs/contracts-library/pull/52)
remain the single workflow delivery. Keep
[PR #47](https://github.com/no-witness-labs/contracts-library/pull/47) open as
the source and comparison baseline until reviewers account for its useful
behavior and the owner approves closure.

This inventory compares PR #47 at
`0dde8ae76e3f8a239bf06685f72327aed4a7c3ef` with the current modular provider.
The original modular checkpoint at `d3bce414a3417b9227fa92f1e0a33672d2829749`
used a 1,000,000-step bound. After semantic review and individual experiments,
the owner approved 5,000,000 steps for UP-001. The [validation history](VALIDATION.md)
keeps the two checkpoints distinct. Full feature parity remains incomplete;
deferred items remain visible gaps in issue #39's acceptance scope.

The `plutus-upv` Lean app is the active prototype workflow. Git history at
`2ef7d11d48018fce48dd17de6fa94ff8d0574d7f` retains the legacy Python runner and
its runner-specific tests. The shared
`scripts/process_blueprint.py` translator remains for other candidate work.
Waiver handling and UP-005/UP-006 integration remain future work for this CLI.

The [CLI quickstart](USER-GUIDE.md) also reuses PR #47's compiled vault fixtures
and attributed source to demonstrate PASS and FAIL. Input-error and timeout
examples demonstrate INCONCLUSIVE. See the [delivery checks](VALIDATION.md)
for their results.

## Current delivery status

The product app now runs all logical validators and all sixteen registered
property-definition/model combinations by default. These comprise two UP-000
Claim/Cancel models, six UP-001 purpose models, two UP-004 Claim/Cancel models,
three UP-012 models, two UP-013 Claim/Cancel models, and one UP-015 Claim reversal binding.
UP-000, UP-004, and UP-013
admit only the original vesting artifact.
These remain experimental workflow bindings, with general property/model readiness
outside this integration.

Repeated `--validator` and `--check`
options filter that work. `--checks-file` instead enables only properties marked
`true`, selecting all their registered combinations. An empty selection is a no-op
and establishes no passing property. The registry supplies executable bindings;
metadata alone cannot add a check or choose executable code.

The callable core is Input → Generator → Executor → Assessor → CheckResult.
The app captures one blueprint, prepares each selected validator once, and repeats
that core over the selected combinations. It owns orchestration, per-validator
PASS/FAIL/INCONCLUSIVE counts, the terminal summary, and local run files/index.
Counts represent combinations, not supporting applicability obligations. The app
assigns no overall verification verdict. The separate human-friendly final report
remains deferred in [issue #83](https://github.com/no-witness-labs/contracts-library/issues/83).
The legacy `universal` command retains its earlier report files and verdict-based
exit codes.

[formal/install.sh](../../install.sh) builds the app and installs a launcher linked
to the retained checkout. `plutus-upv run` defaults to `plutus.json` in the caller's
directory. Installation requires the existing Lean/proof-tool environment; it does
not provision a managed runtime or build the caller's Aiken project.

## Behavior inventory

| Area | PR #47 | Current modular workflow | Disposition |
| --- | --- | --- | --- |
| Input selection | Several validators per command; requires a spend handler and `name.name.handler` titles | App defaults to all logical validators; Input prepares each selected validator, accepts canonical or unambiguous short names, validates explicit V3 metadata, and decodes code | App supplies batch orchestration; additional input formats remain separate work |
| Schema handling | Translates datum and redeemer schemas into bounded symbolic data | Input preserves schemas; UP-001 uses raw redeemer data without schema translation | General schema translation/integration remains open; review the old translation before reuse |
| Parameters | Rejects any entry with a `parameters` field, including an empty array | Input preserves descriptions; current adapters accept absent or empty lists and reject nonempty lists | Typed parameter generation/application remains open; PR #47 does not supply it |
| Candidate checks | UP-000, UP-001, UP-002, UP-004, UP-005, and UP-011 | Registry supplies two UP-000 existential acceptance and two UP-004 existential rejection combinations at 1,000,000 steps, six UP-001 purpose combinations at 5,000,000 steps, three UP-012 combinations (two vesting and one key-datum spend), and one UP-015 Claim reversal combination; CLI filters registered properties | Experimental integration does not establish general readiness; definitions #22/#23/#25/#33/#36, model authoring #89, and further integration #96 remain open |
| Metadata and models | Generator-owned check definitions and transaction builders | Native property/model banks, checked metadata, and fixed executable bindings; selected snapshots follow generated obligations and assessed results | Native banks supply metadata/binding integration; general transaction-model authoring remains open |
| Cases and reachability | Full constructor splits, weaker quick mode, and UNREACHED classification using UP-000 | No schema case splitting or cross-check reachability classification | Review case domains and aggregation before porting spend checks |
| Generated code | Embeds script bytes in the generated Base module; writes modules in the checkout | Embeds script bytes in generated Types; each combination uses a fresh evidence directory | Retain embedded artifacts and isolated execution |
| Execution | Parallel check modules; default four workers and 600 seconds per check module | Sequential combinations; default 300,000 ms per validator/check combination, shared across that combination's generated modules | CLI supplies timeout configuration; parallel scheduling remains open |
| Assessment and outputs | Expected Valid/Falsified results, witnesses, HOLE/REVIEW labels, waivers, expiry, and off switches | Assessor qualifies one CheckResult; app displays combination counts and retains structured results, raw evidence, and a run index; `--checks-file` controls property selection | Final report #83 and waiver/expiry handling remain open; legacy `universal` keeps `report.json`/`report.txt` |
| Commands and installation | Generate-only mode, Nix wrapper, preprocessing, and optional removal of validity hypotheses | Checkout-backed installer and launcher, caller-directory `plutus.json` default, run/test commands, pure generation and callable verification APIs | Managed runtime packaging, developer convenience commands, and semantic options remain open |

The [old generator][old-generator] implements the reference behavior. Current
contracts live in the [Input](../Input/README.md), [Generator](../Generator/README.md),
[Executor](../Executor/README.md), and [Assessor](../Assessor/README.md) guides.
The [developer guide](DEVELOPER-GUIDE.md) maps native definitions, models, bindings,
and app composition. [Reporter](../Tests/Legacy/Reporter/README.md) retains the legacy reporting
API; final client-report design remains separate. The comparison uses source
inspection and earlier modular-provider experiments; PR #47's original proofs
were not rerun. This documentation refresh adds no new proof-suite result.

UP-012 comes from its separate candidate PR #55 and issue #33. It removes the
first signer in supplied vesting and key-datum spend shapes and includes applicability statements.
It is separate from PR #47's UP-002 no-signature checks. Its current adapters use
the pinned vesting artifacts and fixed Claim/Cancel models, plus structurally compatible spending targets
using native TxM-009; broader applicability
and its intended universal meaning remain open.

## Reviewed UP-001 scope

The shared property ID does not make the two generated claims interchangeable.

| Question | PR #47 default path | Modular provider |
| --- | --- | --- |
| Redeemer domain | An integer redeemer for each undeclared purpose | Arbitrary raw `Data` |
| Transaction domain | Bounded transaction builders, schema-shaped datums, and purpose-specific witness/redeemer entries | Full `TxInfo` and per-purpose context fields remain open |
| CEK bound | 5,000,000 steps through `Formal.Common` | Literal `5000000`; the shared `ledgerFuel` remains 1,000,000 |
| Meaning of rejection | Negated acceptance within the bound | Negated acceptance within the bound |

Both claims allow fuel exhaustion to satisfy non-acceptance. Neither establishes
an explicit execution error. The modular domain includes every old constructed
context for the five shared purposes: select its transaction, integer redeemer,
and purpose fields as values of the corresponding open context.

At the same bound, this source-level inclusion means the modular claim covers
the old default-path claim for the same supported program and declared handlers.
The inclusion follows from the definitions; no new machine-checked implication
theorem accompanies it. Neither formula adds a ledger-validity premise; a failing
witness needs review before assigning an on-chain consequence.

The [old acceptance predicates][old-predicates], [current provider][new-provider],
and [current context helpers][new-contexts] pin the relevant definitions. PR #47's
optional `--prep` path has separate execution predicates and also needs review
before reuse. Its `--quick` option restricts schema choices. `--no-validity`
changes spend-check hypotheses but does not affect UP-001, which has no validity
premise.

The original [validation baseline](VALIDATION.md) compares the modular path
with candidate PR #49 at 1,000,000 steps. The later individual experiments all
returned Valid at 5,000,000 steps on the same vesting artifact. Those results
support the stated bounded claims; they do not establish full PR #47 parity.

## Work split and next checkpoint

### Open follow-up tracking

The following issues track the remaining work. They record proposals and pending
decisions; listing an option does not approve its implementation or semantic
changes. The existing definition/foundation issues retain their own scope.

| Remaining work | Open issue |
| --- | --- |
| General typed blueprint integration and validator parameters | [#88](https://github.com/no-witness-labs/contracts-library/issues/88); extracted foundation review stays [#46](https://github.com/no-witness-labs/contracts-library/issues/46) |
| Transaction-model authoring and per-action skeleton proposal | [#89](https://github.com/no-witness-labs/contracts-library/issues/89); composable builders stay [#38](https://github.com/no-witness-labs/contracts-library/issues/38) |
| Aiken project detection, build, and stable blueprint intake | [#90](https://github.com/no-witness-labs/contracts-library/issues/90) |
| Managed Linux prerequisites and runtime delivery | [#91](https://github.com/no-witness-labs/contracts-library/issues/91) |
| Developer commands, counterexample/saved-log inspection, and live progress | [#92](https://github.com/no-witness-labs/contracts-library/issues/92) |
| Review case domains, reachability, quick/preparation modes, and validity handling | [#93](https://github.com/no-witness-labs/contracts-library/issues/93); UP-000 definition stays [#22](https://github.com/no-witness-labs/contracts-library/issues/22) |
| Bounded parallel check scheduling | [#94](https://github.com/no-witness-labs/contracts-library/issues/94) |
| Reviewed exceptions, waivers, and expiry policy | [#95](https://github.com/no-witness-labs/contracts-library/issues/95) |
| Workflow integration of further reviewed candidate families | [#96](https://github.com/no-witness-labs/contracts-library/issues/96); definitions remain in candidate issues #22 through #37, including [UP-012 #33](https://github.com/no-witness-labs/contracts-library/issues/33) |
| Final human-friendly report | [#83](https://github.com/no-witness-labs/contracts-library/issues/83) |
| Wider metadata migration and remaining schema decisions | [#66](https://github.com/no-witness-labs/contracts-library/issues/66), [#65](https://github.com/no-witness-labs/contracts-library/issues/65) |
| Hosted formal CI and its result policy | [#42](https://github.com/no-witness-labs/contracts-library/issues/42) |
| Owner acceptance, retained #47 scope, and closure decision | [#39](https://github.com/no-witness-labs/contracts-library/issues/39) |

### Historical checkpoint evidence

| Stage | Scope | Status |
| --- | --- | --- |
| Light documentation | Inventory retained behavior, deferred features, and semantic differences | Recorded here |
| Heavy semantic review | Compare UP-001 statements, domains, bounds, and assumptions; check each purpose separately | Completed; the owner approved the 5,000,000-step bound |
| Scoped implementation | Update the UP-001 provider, scope text, and fixtures; validate the complete workflow | Implemented; all five checks passed in the complete workflow at 5,000,000 steps |

Remaining work includes the deferred behavior above and review of the supported
workflow with Irfan. Reconcile further behavior one checkpoint at a time,
preserving source attribution. PR #47 closure and issue #39 acceptance remain
owner decisions.

[old-generator]: https://github.com/no-witness-labs/contracts-library/blob/0dde8ae76e3f8a239bf06685f72327aed4a7c3ef/formal/scripts/GenUniversalChecks.lean
[old-predicates]: https://github.com/no-witness-labs/contracts-library/blob/0dde8ae76e3f8a239bf06685f72327aed4a7c3ef/formal/Formal/Common.lean
[new-provider]: ../Tests/Legacy/Candidates/UP001.lean
[new-contexts]: https://github.com/no-witness-labs/contracts-library/blob/d3bce414a3417b9227fa92f1e0a33672d2829749/formal/Formal/Universal/Properties.lean

The TxM-009 pilot added reusable structural admission under `Workflow/Preparation`.
That checkpoint kept the native constructor, property, fuel, and then-current
ten-combination Lean catalogue. UP-000, UP-004, and UP-013 add two combinations each
without changing TxM-009 admission.
Compatible compiled programs need no allowlist entries, but schema compatibility
alone establishes no security role or coverage claim. The supported subset and
conservative rejection behavior are described in the developer guide. This is a
#96 implementation checkpoint related to #88; general parameters, full schema
translation, and property semantics remain deferred.

# Universal properties

Validator-independent properties of the CEK evaluator and V3 ledger model.
They form the first entries of the property catalogue.

| File | Contents |
| --- | --- |
| `Evaluator.lean` | CEK-model fuel stability and success/error properties |
| `Ledger.lean` | Properties assuming V3 `validTxInfo ctx = true` |
| `properties.json` | The catalogue entries |
| [property.schema.json](../../../docs/property-catalogue/property.schema.json) | Shared entry schema (JSON Schema 2020-12) |

## Catalogue entries

Each entry in `properties.json` has five required fields and no others:

| Field | Meaning |
| --- | --- |
| `id` | Stable identifier, e.g. `U-001` |
| `title` | One-line statement |
| `category` | Category name as non-empty text; no predefined values |
| `summary` | The property in plain words, including its limits |
| `theorems` | Fully qualified Lean theorem names; `[]` when none are available |

Use the [shared authoring guide](../../../docs/property-catalogue/property-entries.md)
to add an entry and reference its available Lean theorems.

## Checks

From the repository root, after installing the locked Node dependencies:

```sh
npm run catalogue:check
npm run catalogue:test
```

These checks validate JSON structure against the shared schemas. They do not
build Lean modules, verify theorem names, or inspect proof axioms.

For the scoped Lean check, with the pinned toolchain and Z3 on `PATH`:

```sh
bash formal/check_properties.sh Universal
```

Pass a module name without `Formal.`; use dots for nested modules. This command
validates the selected folder's JSON, builds that module, and checks its listed
theorem names. It does not inspect axioms or check that theorem statements match
the property summaries.

The evaluator proofs are checked by the Lean kernel. The ledger proofs use
`blaster` for `fee_pos`, `ada_balanced`, and `ada_decreases`; the other four use
ordinary Lean proofs. Z3 (4.15.2 on `PATH`) reports those three as SMT-verified,
without a proof term.

## Proposed Universal property: U-001

**Statement.** If execution in the CEK model succeeds with fuel `n`, any fuel
`m ≥ n` returns the same final state:

```lean
theorem cekExecuteProgram_eq_of_success
  (prog : Program) (args : List Term) (n m : Nat)
  (hSuccess : isSuccessful (cekExecuteProgram prog args n))
  (hNM : n ≤ m) :
  cekExecuteProgram prog args m = cekExecuteProgram prog args n
```

**Why it matters.** The model predicate `Formal.Common.validatorAccepts` requires
a unit-valued halt at a fixed fuel budget. Preserving the final state preserves
that outcome with more fuel.

**Scope.** Programs and arguments in the imported CEK model, under the displayed
hypotheses. The program-level theorem uses default builtin semantics;
`runSteps_eq_of_halt` covers all builtin semantic variants. No ledger-validity
assumption is required.

**Limit.** The theorem assumes a successful halt. Fuel exhaustion produces
`Error`, as runtime failures do. An `Error` result at one budget does not by itself
establish rejection at a larger budget.

**Proof.** Induction on the step count (`runSteps_eq_of_halt`), kernel-checked.

## Caveats on the ledger properties

All ledger entries assume V3 `validTxInfo ctx = true`. They prove properties of
the model, not correspondence with Cardano ledger validation.
`ada_balanced_of_simple_tx` adds context restrictions and still concludes the
same model balance equation.

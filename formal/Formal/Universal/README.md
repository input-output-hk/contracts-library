# Universal properties

Properties that hold for every validator, with machine-checked Lean proofs. They
form the first entries of the property catalogue.

| File | Contents |
| --- | --- |
| `Evaluator.lean` | Properties of the CEK evaluator, for any program and Plutus version |
| `Ledger.lean` | Properties of every transaction the V3 ledger model (`validTxInfo`) accepts |
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

The evaluator proofs are checked by the Lean kernel. The ledger proofs use
`blaster`, so they are checked by Z3 (4.15.2 on `PATH`) and reported as
SMT-verified with no proof term.

## Proposed Universal property: U-001

**Statement.** If a program halts within `n` CEK steps on some arguments, then for
any `m ≥ n` it halts in the same final state:

```lean
theorem cekExecuteProgram_eq_of_success
  (prog : Program) (args : List Term) (n m : Nat)
  (hSuccess : isSuccessful (cekExecuteProgram prog args n))
  (hNM : n ≤ m) :
  cekExecuteProgram prog args m = cekExecuteProgram prog args n
```

**Why it matters.** Contract proofs decide acceptance by running the compiled
validator with a fixed step budget (`Formal.Common.validatorAccepts`). This
property shows an acceptance cannot be overturned by a larger budget: the run ends
in the same state and returns the same value.

**Scope.** Every program, every argument list, every Plutus version. No ledger
assumptions.

**Limit.** Failure is not preserved. Running out of steps ends in the same `Error`
state as a genuine failure, so a rejection at one budget says nothing about a
larger one. Rejection results depend on the budget being large enough.

**Proof.** Induction on the step count (`runSteps_eq_of_halt`), kernel-checked.

## Caveats on the ledger properties

The ledger properties are about the V3 model, not the chain itself. U-003 and
U-004 and U-006 also hold on chain. U-005 is the model's balance rule (input ada =
output ada + fee); the chain also counts withdrawals, refunds, deposits and
donations, so transactions with those are outside what the model accepts.
`ada_balanced_of_simple_tx` states the scope where the two rules agree.

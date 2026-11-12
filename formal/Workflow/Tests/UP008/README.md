# UP-008 workflow scenarios

The UP-008 scenarios preserve an expected official FAIL for guarded rejection
after adding one unit of a fixed junk asset to the original linear-vesting Claim
continuation. They use
[UP008/Definition.lean](../../../Formal/Properties/Universal/UP008/Definition.lean),
the original compiled fixture at [UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json),
and TxM-007 Claim through the native catalogue, app API, and engine. One registered
combination produces a main obligation and linked applicability, both using the
1,000,000 CEK-step bound.

Run the automated suites from `formal/`:

```sh
lake exe workflow_up008_tests
lake exe workflow_up008_tests --unit
lake exe workflow_up008_tests --control
lake exe workflow_declarative_up008_tests
```

The automated scenario invokes the app API. The public CLI is a separate check:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-008 --timeout-ms 300000
```

The reference expectation is Falsified for `junkToken_claim` and Valid for
`junkToken_claim_applies`, producing one official FAIL combination. Both native
goals still expect Valid; the regression test requires the reference's actual
Falsified observation and resulting FAIL. A passing regression suite therefore
does not mean the reference property passes. These expectations do not replace
fresh execution evidence. The
[validation record](../../../Formal/Properties/Universal/UP008/VALIDATION.md)
records the checked commands and their limits.

The terminal's `Review` path links the `UP-008-v1-TxM-007` directory, containing
`check-result.json`, execution records, and generated `Types.lean`, `Tx.lean`,
and `Checks.lean`. Shared captured sources include the selected property and model
modules. Generated output stays under ignored `formal/output/` folders.
A zero app exit means orchestration and retention completed; the individual
property remains FAIL when its qualified observations falsify the rule.

## Mutation, guards, and applicability

The mutation appends an input containing `a` lovelace and one unit of the fixed
`zzzzjunk` / `zzzzjunk` asset. It adds the junk asset to the first continuation
and appends a separate output returning the lovelace to the unrelated key.
The integer `a` is lovelace, not token quantity or count. The continuation keeps
its address, datum, reference-script field, and existing value entries; the
original payout and other context fields remain unchanged.

The main goal retains four premises: baseline validity, bounded baseline
acceptance, bounded explicit rejection after redirection, and validity after
the junk-asset mutation. Applicability requires a witness satisfying all four.
Neither Valid nor Falsified main observations establish a guarded verdict without
trustworthy linked applicability.

Continuations match the spent input's payment credential alone. The separate
`redirectContinuations` guard changes matching outputs' addresses and removes
their datums. Rejection of that combined change does not independently prove
reliance on either field or on asset composition. Rejection means an error or
non-unit halt within 1,000,000 CEK steps; fuel exhaustion does not count.

Cancel is not registered. TxM-008 supplies no continuation, making redirection
the identity and its acceptance/rejection premises incompatible. The preserved
standalone Cancel applicability is an expected falsification; its vacuous primary
result provides no mutation coverage.

## Admission and control

The property admits only the original reference fixture. Its run declaration
skips the second vesting artifact recognized by native model admission. Native
admission rejects the incompatible vault. Both paths generate no proof
obligations and establish no passing property.

The enforcing control executes the frozen compiled
[enforcing program](../../../Formal/Properties/Universal/UP008/Tests/Standalone/EnforcingControl.lean).
Its [Aiken source](../../../Formal/Properties/Universal/UP008/Tests/Standalone/Project/validators/enforcing.ak)
finds its own input and requires the first output to keep that input's script
payment credential and contain zero of exactly `zzzzjunk` / `zzzzjunk`.
It checks the exact asset's quantity, not total token count. The control preserves
the symbolic model script credential, mutation, four premises, and bound. It
expects Valid main and applicability observations, producing a test-only PASS.
A timeout or compiler/solver error does not satisfy those expectations.

The control uses a distinct test identity with official property/binding metadata
set to null. Its retained `input.json` contains the executed control blueprint;
`reference-input.json` contains the original vesting fixture and is marked as
reference-only. `control-result.json` records the assessment and executed program
hash; `execution.json` links the observations, generated sources, and logs.
The retained `control-project/` folder includes the checked Aiken source,
configuration, lockfile, and provenance manifest.
The [control implementation](PassingControl.lean) adds no official property/model
binding and no automatic Aiken build. The original reference's applicable
falsification supplies the counterpart to this enforcing control.

Separate synthetic observations check that missing, inconclusive, or falsified
applicability leaves either a Valid or Falsified main observation
unresolved. These controls test assessment policy without proving a validator
property. `--unit` checks preparation and structure without invoking the solver;
the default suite includes app/engine execution, the enforcing control, and
retained results. Use `--control` to run only the compiled enforcing control.

## Scope and earlier evidence

The [property guide](../../../Formal/Properties/Universal/UP008/README.md) records
the fixed model, symbolic script credential, original-artifact restriction, and
Blaster trust boundary. Falsification refutes this guarded fixed-asset rejection
rule. It establishes neither a configurable token-count limit nor token flooding,
locked funds, a vulnerability, arbitrary transaction coverage, or ledger
reachability. A workflow timeout leaves the affected claim unresolved.
[Issue #29](https://github.com/no-witness-labs/contracts-library/issues/29) retains
the wider token-count rule, and [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96)
retains broader integration work.

The [standalone guide](../../../docs/UP008.md) preserves earlier results, direct
commands, and the expected false Cancel applicability diagnostic. Those
observations remain historical. The [workflow test index](../README.md) lists
aggregate registration; neither suite registration nor this guide claims a
complete aggregate pass.

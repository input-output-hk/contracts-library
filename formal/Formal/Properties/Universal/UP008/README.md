# UP-008: guarded rejection of one fixed junk asset

UP-008 checks rejection after adding one unit of one fixed asset to the first
continuation in the original linear-vesting Claim model. The reference artifact
is expected to falsify this guarded rejection rule, with Valid linked
applicability, producing one official FAIL combination. This preserves the
standalone expectation; it does not establish token flooding, locked funds, or
a vulnerability.

[Definition.lean](Definition.lean) owns one primary statement and its supporting
applicability predicate; [metadata.json](metadata.json) records their scope.
The statement keeps all four premises from the standalone Claim formula:

1. **Baseline validity:** the original context satisfies `validScriptContext`.
2. **Baseline acceptance:** the validator accepts that context within 1,000,000
   CEK steps.
3. **Redirect rejection:** the validator explicitly rejects `redirectContinuations`
   within the same bound. This helper changes every matching continuation's
   address to an attacker key address and removes its datum.
4. **Changed-context validity:** the junk-asset mutation leaves the context
   model-valid.

Under those premises, the validator must explicitly reject the mutation within
1,000,000 CEK steps. An error or non-unit halt counts as rejection; fuel exhaustion
does not. Applicability requires a witness satisfying all four premises.
Both PASS and FAIL require trustworthy linked applicability; missing, falsified,
timed-out, or untrusted applicability leaves the guarded claim unresolved.

## Exact mutation

[Definition.lean](Definition.lean) preserves the original
[addJunkFrom mutation](../../../Support/CandidateHelpers.lean). It appends an
input at the fixed unrelated key. That input holds `a` lovelace and one unit of
the asset whose policy and name are both `zzzzjunk`. The helper adds the junk
asset to the first continuation's value and appends a separate output returning
the `a` lovelace to the unrelated key. The continuation keeps its address, datum,
reference-script field, and existing value entries; the original payout and
other context fields remain unchanged.

The quantified integer `a` is added lovelace, not token quantity or token count.
The quantified `r` identifies the appended input; changed-context validity
constrains admissible references and transaction bookkeeping. The junk quantity
is always one, and its policy and name are fixed. This check implements no
configurable limit on distinct tokens.

Continuations match the spent input's payment credential alone. The separate
redirect guard changes both address and datum, so its rejection does not
independently establish reliance on either field or on asset composition.

## Run the reference check

With the [workflow prerequisites](../../../../Workflow/Docs/USER-GUIDE.md#prepare-once)
available, run from `formal/`:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-008 --timeout-ms 300000
```

[Run.lean](Run.lean) registers only TxM-007 Claim. Its single combination emits
two linked obligations:

| Role | Obligation | Expected reference observation | Native goal expectation |
| --- | --- | --- | --- |
| Primary | `junkToken_claim` | Falsified | Valid |
| Applicability | `junkToken_claim_applies` | Valid | Valid |

Both native expectations stay Valid. The expected Falsified primary observation
therefore produces FAIL when qualified by Valid applicability. The regression
test requires that official failure; a passing test suite does not mean the
reference property passes. These expectations do not record a fresh run. Consult
the [validation record](VALIDATION.md) and retained execution evidence.

Open the terminal's `Review` path. The
`validators/linear_vesting.linear_vesting/UP-008-v1-TxM-007/` directory retains
generated `Types.lean`, `Tx.lean`, and `Checks.lean`, plus result and execution
records. The shared source snapshot captures imported property and model modules.
A zero app exit records completed orchestration and retention, separately from
the FAIL property outcome.

## Scope and admission

The run declaration admits only the original compiled artifact in
`Workflow/Tests/UP012/Inputs/plutus.json`. It skips the second vesting artifact
recognized by native TxM-007 admission. Unknown artifacts remain unsupported.
These paths produce no proof obligations and establish no passing property.
Default selection and the all-enabled example switch file include UP-008.

TxM-007 starts with two inputs and two outputs: a script continuation with an
inline datum first, then a payout. It uses one signer, one vested asset under
fixed `policyA`, and key credentials for the beneficiary and locker. The mutation
adds a third input and output. The model keeps its script credential symbolic,
without constraining it to the supplied program's hash. It excludes reference
inputs, minting, and withdrawals. This check does not cover arbitrary output
order, multiple continuations, other junk assets, or variable junk quantities.

Cancel is not a runnable UP-008 combination. TxM-008 has no continuation, so
redirection leaves its context unchanged. An accepted baseline cannot also meet
the redirect-rejection premise. The [standalone guide](../../../../docs/UP008.md)
retains Cancel's vacuous Valid primary result and expected Falsified applicability.
Neither supplies Cancel mutation coverage.

Results retain the fixed model, artifact, 1,000,000-step allowance, and Blaster
SMT trust boundary. An applicable falsification refutes this guarded fixed-asset
rejection rule. It does not establish arbitrary token acceptance, a token-count
limit, ledger reachability, source correspondence, or funds loss. The configurable
token-count rule remains open in
[issue #29](https://github.com/no-witness-labs/contracts-library/issues/29), and
broader integration remains in [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96).
The CEK bound is separate from ledger execution budgets and the CLI wall-clock
timeout. A timeout or compiler/solver error leaves the affected claim unresolved.

## Tests and provenance

Focused commands from `formal/`:

```sh
lake exe workflow_declarative_up008_tests
lake exe workflow_up008_tests
lake exe workflow_up008_tests --unit
lake exe workflow_up008_tests --control
```

[Tests.lean](Tests.lean) checks the Claim-only binding, original-artifact
restriction, formula/model correspondence, and mutation field preservation.
The [workflow scenario](../../../../Workflow/Tests/UP008/README.md) exercises the
native app API, retained output, skip paths, and linked applicability assessment.
The public CLI command above is a separate end-to-end check. Both suites are
registered in the aggregate; registration does not claim a complete aggregate pass.

The compiled [enforcing control](Tests/Standalone/EnforcingControl.lean) finds its
own input and requires the first output to keep its script payment credential
and contain zero of exactly `zzzzjunk` / `zzzzjunk`. It checks that asset's
quantity, not the number of token entries. The original vested policy `policyA`
differs from the junk policy, even if the symbolic vested name equals `zzzzjunk`.
The control retains the model, mutation, four premises, and CEK bound. Its
expected primary and applicability observations are both Valid, producing a
test-only PASS.

The control retains its actual compiled input and script hash under a distinct
test identity. Official property/binding metadata is null, and the original
vesting input is retained separately as reference-only evidence. The control
adds no official UP-008 combination. Use `--control` to run it separately.

The standalone guide preserves the original formulas, attribution, dependency
pins, and measured results. Those historical observations do not establish a
fresh workflow run or complete the wider property and model work.

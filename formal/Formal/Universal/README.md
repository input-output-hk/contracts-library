# CEK evaluator sanity checks

Draft description and specification for [property `PROP-001`](properties.json).
The [proofs](Evaluator.lean) concern the Lean CEK evaluator, independently of
a particular validator.

## Specification

For any program `p : Program`, arguments `args : List Term`, and step limit
`fuel : Nat`, let `r = cekExecuteProgram p args fuel`.

- **Success excludes error:** `isSuccessful r → r ≠ State.Error`.
  Proof: `Formal.Universal.Evaluator.success_not_error`.
- **Zero fuel fails:** `isUnsuccessful (cekExecuteProgram p args 0)`.
  Proof: `Formal.Universal.Evaluator.zero_fuel_always_fails`.

Here, successful means a `State.Halt` result; unsuccessful means `State.Error`,
as defined in the locked library's
[result predicates](https://github.com/input-output-hk/PlutusCoreBlaster/blob/4ef48606303c45225d3ed2e2a87fc50280a763b7/PlutusCore/UPLC/Utils.lean#L26).

## Scope

These statements describe the evaluator model, not a validator's business rules
or a ledger-wide security guarantee. No concrete validator snapshot is involved.
Fuel counts evaluator steps, not ledger CPU/memory execution units; see the
locked [step-limited evaluator](https://github.com/input-output-hk/PlutusCoreBlaster/blob/4ef48606303c45225d3ed2e2a87fc50280a763b7/PlutusCore/UPLC/CekMachine.lean#L242).

The separate `smoke` theorem checks Blaster setup; it is not part of this sample's
property specification.

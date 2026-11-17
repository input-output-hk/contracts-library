# Reusable preparation fixtures

These validators were authored for the TxM009 reusable-preparation pilot. They
exercise preparation independently of the original vault fixtures. They are test
fixtures, not production contracts or general property proofs.

From this directory, with Aiken v1.1.21 and stdlib v3.0.0 available, run:

```sh
aiken fmt lib/preparation_types.ak validators/controller_gate.ak validators/missing_signature.ak validators/never_accept.ak
aiken build
```

The generated `plutus.json` is ignored. The fixed blueprint at
`../../UP012/Inputs/reusable.json` retains the three spend entries and their
complete definitions from that build. Its compiled code is the oracle for these
fixtures. Each script is unparameterized Plutus V3. All three scripts have a datum
encoded as constructor 0 with one bytes field named `controller`, and a typed
`Withdraw` redeemer encoded as constructor 0 with no fields.

| Spend target | Behavior | Expected pilot outcome |
| --- | --- | --- |
| `controller_gate.controller_gate.spend` | Requires the controller signature and exactly one input. | Signer-removal PASS within the model, after applicability succeeds. |
| `missing_signature.missing_signature.spend` | Requires exactly one input but omits the controller signature check. | Signer-removal FAIL with applicability established. |
| `never_accept.never_accept.spend` | Always rejects. | Failed applicability; must not report PASS. |

These expected outcomes refer only to the current model: one script input, one
ADA output, one signer, and varying input ADA and fee. They do not establish
coverage of arbitrary transactions, other script purposes, or production
contracts. The complete UP-012 suite produced these expected outcomes, including
the failed applicability control. The terminal displays that control as ERROR;
its saved assessment remains INCONCLUSIVE, never PASS.

Aiken build completed successfully. All three compiled programs differ from one
another and from every validator in the original `UP012/Inputs/plutus.json`.

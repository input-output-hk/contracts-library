# UP-009: one hashed-datum vault spend

This standalone candidate asks whether the frozen owner-checking vault has at
least one accepted spending context whose own input stores a datum hash and
whose datum witness supplies the corresponding datum. The statement requires
`validScriptContext = true` in the pinned Lean ledger model and a unit halt
within 1,000,000 CEK steps. This is an existence claim for one fixed example;
it does not quantify over all vault transactions or require every accepted
inline-datum spend to remain accepted after conversion to a datum hash.

## Consolidation status

This is an incomplete implementation checkpoint. The owner approved preparing
it for consolidation so work can continue on fresh branches from the shared
structure. This exception does not complete UP-009's checkpoint-1 proof goal.

Definition/support compilation passed. The earlier proof attempt reached its
300-second limit without a solver verdict. On 2026-11-03, a separately authorized
attempt stopped after 1.710 seconds in `actualDatum_serializes`: `decide` could
not reduce the datum-encoding equality. The eight Blaster obligations and the
existential assembly did not run. No property or control result is established;
the structural error does not show that the encoding equality is false.

The saved proofs remain opt-in. Later structural moves update module references
and artifact paths without changing their statements or proof strategy. Further proof execution
requires a new bounded-run decision. Proof completion stays tracked in
[#30](https://github.com/no-witness-labs/contracts-library/issues/30);
native-model reconciliation and app integration remain
[#89](https://github.com/no-witness-labs/contracts-library/issues/89) and
[#96](https://github.com/no-witness-labs/contracts-library/issues/96).

## Source and model

The source is in `Formal/Vault/Blueprint/`, relative to `formal/`:

- `Types.lean` loads the frozen compiled program and defines bounded acceptance
  and rejection. Rejection requires an error or non-unit halt; fuel exhaustion
  is not rejection.
- `Tx.lean` defines the concrete witness and controls.
- `UP009Definition.lean` states the existential property. It requires the resolved
  own input to use the vault's script credential, its datum hash to be Blake2b-256
  of the serialized supplied datum, and its datum-map lookup to match that datum.
- `UP009Structural.lean` contains the input/datum lookup lemmas and the unfinished
  serialization proof.
- `UP009.lean` contains the eight Blaster obligations and the intended existence
  proof assembly.

The witness has one script input containing 2 ADA, one owner-key output containing
1.8 ADA, a 0.2 ADA fee, and one owner signature. The owner is a fixed 28-byte key
hash. The datum is `Constr 0 [B owner]`, and the redeemer is `Constr 0 []`.
Transaction IDs are fixed 32-byte values. The validity interval starts at zero
and has no upper bound. Reference inputs, minting, certificates, withdrawals,
votes, proposals, and treasury fields are absent.

The datum hash is computed by the dependency's transparent
`Cryptograph.Blake2b.blake2b_256`, using the actual CBOR bytes without UTF-8
re-encoding. The unfinished `actualDatum_serializes` proof is intended to connect those bytes to
`PlutusCore.Cbor.encodeData actualDatum`. The witness does not assume that the
ledger model's datum-map validation checks cryptographic hashes.

The following results are requirements for the pending checks, not observations:

| Context | Required model result | Required validator result |
| --- | --- | --- |
| Hashed input, matching datum map, owner signature | Valid | Accepts |
| Missing datum-map entry, supplied datum retained | Invalid | No execution claim |
| Wrong datum-map value, supplied datum retained | Invalid | No execution claim |
| Missing owner signature, matching datum map retained | Valid | Rejects within the bound |
| Inline input datum, empty datum map, owner signature | Valid | Accepts |

The missing-map control deliberately retains `Some actualDatum` in the spending
script information. It checks consistency between the supplied datum and the
witness map; it makes no claim that every V3 input lacking a datum witness is
invalid. The inline control is a separate concrete example, not a universal
preservation theorem.

## Frozen source and program

`Inputs/` copies the existing UP001 fixture from contracts-library commit
[`40776bf10d2adb07b76307a571dc36b0106f0c7b`](https://github.com/no-witness-labs/contracts-library/tree/40776bf10d2adb07b76307a571dc36b0106f0c7b/formal/Workflow/Tests/UP001/Inputs).
The target is `vault.vault.spend` in `plutus.json`, with source in
`validators/vault.ak`. Its datum names the owner, and its spending handler checks
that the owner appears in `extra_signatories`. The original complete fixture is
retained, including its unused buggy sibling, manifest, and lock file.

The blueprint records Aiken `v1.1.19+e525483`, Plutus V3, and stdlib `v3.0.0`.
Aiken CLI `v1.1.21+42babe5` independently recomputed the target script hash from
the frozen compiled bytes with `aiken blueprint hash -m vault -v vault`:

```text
7ee33b926834bd7d983ca9d433cee0cc1918ed5bcb5f78ab795d7057
```

The result matches the blueprint and the script credential in `Types.lean`.
This hash check does not constitute a rebuild with the recorded compiler.

## Verification boundary

Both proof modules are intentionally outside the default `Formal` import graph.
After the pinned dependencies are prepared, definition-only compilation is:

```sh
lake build Formal.Support.Compatibility Formal.Vault.Blueprint.Types Formal.Vault.Blueprint.Tx Formal.Vault.Blueprint.UP009Definition
```

The following opt-in target currently fails at the structural serialization
precheck. Execute it only as part of a separately authorized bounded proof run:

```sh
lake build Formal.Vault.Blueprint.UP009
```

The step limit is a CEK execution bound, not a Cardano CPU or memory budget.
Successful checks establish only this frozen vault example under the pinned
ledger and evaluator models. They do not establish transaction submission,
deployment coverage, or general support in the property/model bank or app.

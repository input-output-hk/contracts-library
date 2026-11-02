# Blueprint extraction and candidate checks

This foundation extracts the type-generation pass from
[sayyadirfanali's work in PR #44](https://github.com/no-witness-labs/contracts-library/pull/44)
at `99a5734f0e036b6abfb4c3f121a298e35fa2eff6`.
It also extracts the `otherPurpose` check (UP-001) and the selected
`malformedRedeemer` cases (UP-005), preserving their original statements.

From `formal/`, using a chosen blueprint snapshot:

```sh
python3 -I scripts/process_blueprint.py ../onchain/plutus.json linear_vesting --cbor-only
python3 -I scripts/process_blueprint.py ../onchain/plutus.json linear_vesting --out Formal/Vesting/Linear/Blueprint
```

The first command copies the blueprint's compiled hex to
`Scripts/linear_vesting.linear_vesting.cbor`.
The second writes only `Types.lean`: types, `IsData` instances, script arguments,
the imported program, and bounded acceptance/rejection predicates.
Without `--check`, existing transaction and check files stay unchanged.
Use `module.validator` when a short validator name is ambiguous.

With the existing pinned Lean dependencies available, compile the new modules:

```sh
lake build Formal.Universal.Properties Formal.Vesting.Linear.Blueprint.Types
```

No automatic Aiken rebuild or dependency update occurs.
Type generation supports Plutus V3; recursive schema definitions fall back to
`Data` with a warning.
The copied bytes and recorded blueprint hash are not independently validated
for provenance or CBOR correctness.
CEK fuel is a step bound, not a Cardano CPU or memory budget.

Run the stdlib-only Python tests from the repository root:

```sh
python3 -I -B -m unittest discover -s formal/tests -p 'test_process_blueprint.py'
```

The synthetic fixture is not an executable validator.
Python tests check translation and file behavior, not Lean compilation or proof validity.

## Undeclared purposes (UP-001)

After copying CBOR as above, generate the selected checks and run them:

```sh
python3 -I scripts/process_blueprint.py ../onchain/plutus.json linear_vesting --out Formal/Vesting/Linear/Blueprint --check otherPurpose
lake clean formal
lake build Formal.Universal.Properties Formal.Vesting.Linear.Blueprint.Types
lake env lean Formal/Vesting/Linear/Blueprint/Checks.lean
```

`--check otherPurpose` replaces `Types.lean` and `Checks.lean`; it neither requires
nor writes `Tx.lean`. The root-package clean forces a fresh CBOR import because
Lake does not track the external CBOR file. Dependency build outputs stay cached.

For each purpose without a declared handler, the check keeps the original
negated acceptance claim, such as `¬ accepts ledgerFuel (EveryMint.ctx t r)`.
The full transaction, redeemer, purpose fields, and script parameters are variables.
The check covers no success within 1,000,000 CEK steps, including fuel exhaustion;
it does not require an explicit error or establish a ledger-budget bound.
All declared handlers means no goals apply, which the generator reports.
Blaster results use its `blasterProven` axiom without a reconstructed proof term.

## Malformed redeemers (UP-005)

After copying CBOR as above, generate and run the selected cases:

```sh
python3 -I scripts/process_blueprint.py ../onchain/plutus.json linear_vesting --out Formal/Vesting/Linear/Blueprint --check malformedRedeemer
lake clean formal
lake build Formal.Universal.Properties Formal.Vesting.Linear.Blueprint.Types
lake env lean Formal/Vesting/Linear/Blueprint/Checks.lean
```

The check option replaces `Types.lean` and `Checks.lean`; it needs no `Tx.lean`.
The root-package clean forces a fresh CBOR import, retaining dependency builds.

Cases include selected wrong top-level forms, two absent constructor tags, one
extra field, a missing last field, and selected wrong field kinds, where the
type supplies those cases. Unknown tags come from the blueprint's actual indices.
These cases are not exhaustive. Field cases fix list/map fields to empty and
some nested alternatives to one constructor. Untyped redeemers generate no goals.

Each claim keeps `¬ accepts ledgerFuel (...)`, with the full modeled transaction,
purpose fields, and script parameters open. No success within 1,000,000 CEK steps
includes fuel exhaustion; it does not establish an explicit error or a ledger
budget bound. Blaster uses `blasterProven` without a reconstructed proof term.

# Settings property catalogue

Milestone 1.3 develops the Settings property catalogue, Lean proofs for the
selected properties, and a tutorial with reproducible examples.

Prepare against the Settings implementation at IO commit `42048b7`.
Record the exact source commit, compiler, Plutus version, and script hash with
each validator artifact. Record the parameter values when proofs use a
parameterized instance. [Settings source and specification](https://github.com/input-output-hk/contracts-library/blob/42048b7af58ca12a6c5bbeb1e152079048ffa460/docs/settings/spec.md)

Use the existing schemas as the source of truth for the catalogue records.
Validate each record against its schema before adding it to the catalogue.

- [Property definitions](https://github.com/no-witness-labs/contracts-library/blob/875bf16d05a9f727f7350380f8f0afea0c83dedc/formal/Formal/Universal/Properties/property-definition.schema.json)
- [Transaction models](https://github.com/no-witness-labs/contracts-library/blob/875bf16d05a9f727f7350380f8f0afea0c83dedc/formal/Formal/Universal/TxModels/transaction-model.schema.json)
- [Combined checks](https://github.com/no-witness-labs/contracts-library/blob/875bf16d05a9f727f7350380f8f0afea0c83dedc/formal/Formal/Universal/Workflow/Metadata/combined-check.schema.json)

Create each follow-up branch from `fv/m1.3-settings`. Target that branch when
opening a follow-up pull request.

# Input component

Input's Lean implementation discovers logical validators, prepares one selected
validator at a time, validates its embedded compiled code, and preserves the
metadata Generator needs. The app reuses each prepared validator across its checks. The
[workflow decisions](../README.md) define its scope.

## Use and test

With the repository's pinned Lean dependencies prepared, run from `formal/`:

```sh
lake build Workflow workflow_input_tests
lake exe workflow_input_tests
```

Import `Workflow.Input` to use:

- `Workflow.Input.discover source`: return canonical logical validator names in
  blueprint order, grouping entries for different handlers. Discovery checks the
  shared JSON/version/title profile without decoding each compiled artifact.
- `Workflow.Input.parse source selector`: read blueprint text and return an
  `Except Error InputResult`.
- `Workflow.Input.read path selector`: read a file and return the same result
  in `IO`, preserving the input file.
- `Workflow.Input.readWithSource path selector`: return the optional readable
  source and validation result from one read. The source remains available on
  validation errors; file-read errors return no source snapshot.

`InputResult.target` is Generator's handoff. It contains the canonical name,
explicit Plutus version, original encoded code, handler descriptions, ordered
parameter descriptions, and optional schema definitions and compiler metadata.
`sourceText` and `sourcePath` retain provenance separately. Input decodes the
program internally for validation; it does not expose a decoded program field.

The app captures the blueprint text once, discovers its names, and calls `parse`
on that same source for each selected validator. A malformed compiled artifact
fails that validator's preparation while other validators can continue. Invalid
shared JSON or title structure prevents discovery; unsupported selected handler
purposes remain preparation errors.

## Supported blueprint profile

The first adapter supports the current Aiken-style Plutus V3 blueprint layout:

- The document contains a `preamble` object with explicit `plutusVersion: "v3"`
  and a `validators` array.
- Each entry has a `module.validator.handler` title. Module paths can contain
  `/`. Select the full `module.validator` name or an unambiguous short name.
- Entries for one validator share the exact encoded `compiledCode` and parameter
  descriptions. Duplicate handlers and inconsistent entries produce errors.
- Supported purposes are `spend`, `mint`, `withdraw`, `publish`, `vote`, and
  `propose`. Input retains the `else` fallback separately from declared purposes.
- A declared handler requires a redeemer description. Datum descriptions are
  optional. Each supplied argument description contains a schema object.
- Optional parameters remain absent or retain their declared order. Input does
  not apply values. An explicit empty array remains distinct from absence.
- Optional definitions and compiler metadata are objects when present.
  Optional titles, descriptions, and declared hashes are strings when present.

This profile does not cover every CIP-57 blueprint layout. Unsupported title
profiles and selected handler purposes produce explicit errors. Input preserves
schema JSON and definitions without translating types or validating the full
schema vocabulary; Generator owns translation and reports unsupported schemas.

## Compiled-code validation

Input uses the pinned PlutusCoreBlaster dependency's error-returning
[`singleCborEncodedScriptFromHex?` helper](https://github.com/input-output-hk/PlutusCoreBlaster/blob/4ef48606303c45225d3ed2e2a87fc50280a763b7/PlutusCore/UPLC/ScriptEncoding/Basic.lean#L67).
The helper decodes hexadecimal, Concise Binary Object Representation (CBOR), and
the serialized Plutus program. Input also uses the existing CBOR decoder to
reject bytes trailing after the encoded script.

Success requires successful decoding. Input neither executes the validator nor
runs a solver. It preserves supplied code and declared hashes without applying
parameters or checking correspondence to source code or metadata claims.

## Errors and metadata

Errors contain a category, field path, and explanation. Categories distinguish
malformed JSON, missing fields, malformed fields, unsupported input, selection
errors, inconsistent handlers, decoding errors, and file errors.

Missing required fields produce an error. Optional fields remain absent without
guessed values; an explicit null is not an omitted field. Schema content stays
declarative. A successful read does not establish that a selected Generator can
support every schema or parameter configuration.

## Test boundary

The test implementation and fixtures live under `Workflow/Tests/Unit/Input/`;
see the [unit test guide](../Tests/Unit/README.md).


The native Lean fixture harness checks discovery/grouping, invalid-code isolation,
selection, multiple validators and
purposes, module paths, parameter order, absent versus empty metadata, source
preservation, file errors, and malformed inputs. It includes invalid hex,
truncated CBOR, rejected programs, and trailing bytes. These tests use no Aiken
build, property generator, or solver.

The fixture's compiled program is a small decoding example from the dependency's
script-encoding tests. It is not evidence of a validator's behavior. Read-only
smoke checks also succeeded on the repository blueprint's linear-vesting,
settings, and DAO-proposal entries, including their parameter descriptions.

Standalone CBOR files, function targets, other Plutus versions, and additional
blueprint profiles remain later extensions. The app connects Input to
[Generator](../Generator/README.md), [Executor](../Executor/README.md), and
[Assessor](../Assessor/README.md), then retains individual results and renders
its terminal summary. Final human-friendly reporting is separate work.

# Validator snapshot metadata

In the existing `formal/` tree, place `validator-metadata.json` beside the
validator's `properties.json`:

```text
<validator-property-folder>/
├── properties.json
└── validator-metadata.json
```

One snapshot covers every property entry in that folder. This association adds
no fields to the property-entry schema.

Use [validator-metadata.schema.json](validator-metadata.schema.json). All ten
non-compiler fields are mandatory. Compiler fields are optional; omit unknown
values. Do not add fields.

## Fields

| Field | Meaning |
| --- | --- |
| `validator_name` | Actual validator name; full entry title where applicable. |
| `source_repository` | Canonical HTTPS URL of the IO upstream repository. |
| `source_commit` | Full 40-character commit SHA in that IO repository, not the fork's working commit. |
| `file_name` | Repository-relative `.ak` path at that commit. |
| `sha256` | SHA-256 of the named file's raw bytes, including comments and formatting; excludes imported files and CBOR. |
| `cbor_hex` | Full compiled validator's Concise Binary Object Representation (CBOR) hex, not a hash. |
| `cbor_format` | `single_cbor_hex` or `double_cbor_hex`, matching the stored wrapping. |
| `plutus_version` | Compiled validator's language version: `v1`, `v2`, or `v3`. |
| `parameterization_state` | State of the stored script's fixed parameters, as below. |
| `applied_parameters` | Already-applied parameter values as complete CBOR-hex strings, in application order. |
| `compiler_name` | Compiler name, if known. |
| `compiler_version` | Exact compiler version and build identifier, if known. |

## Fixed parameters

These are fixed script parameters, not datum, redeemer, or transaction inputs.

| State | Meaning | `applied_parameters` |
| --- | --- | --- |
| `unparameterized` | No fixed parameters exist. | `[]` |
| `unapplied` | Parameters exist; none applied. | `[]` |
| `partially_applied` | Some parameters applied. | Non-empty list. |
| `fully_applied` | All parameters applied. | Non-empty list. |

Record only values already applied to the script in `cbor_hex`, not values
chosen for documentation.
Determine partial versus full application from the validator's declared parameters.

## Validation limits

The schema checks structure, types, formats, and parameter-list lengths. It
does not verify commits, recompute hashes, decode CBOR, or establish compilation
or proof results. Folder association alone does not prove that the proofs
concern the recorded script.

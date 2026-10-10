# Validator snapshot metadata

For a property set about a specific validator, snapshot metadata identifies the
source revision and compiled script that the properties concern.

## Placement and association

Keep the existing `formal/` layout. Place `validator-metadata.json` beside the
validator's `properties.json`:

```text
<validator-property-folder>/
├── properties.json
└── validator-metadata.json
```

The metadata describes the snapshot for all entries in that folder's
`properties.json`. The shared folder supplies the association, without adding
a reference field to the property entries or changing their schema.

## Metadata contents

Use [validator-metadata.schema.json](validator-metadata.schema.json). The
10 non-compiler fields are mandatory. Compiler name and version are optional;
omit them when unknown. No additional metadata fields are allowed.

| Field | Meaning |
| --- | --- |
| `validator_name` | The selected validator's name; use the full entry title where applicable. |
| `source_repository` | The canonical HTTPS URL of the IO upstream repository. |
| `source_commit` | The exact full commit SHA in that IO repository, not a fork working-branch commit. |
| `file_name` | The repository-relative `.ak` source path at that commit. |
| `sha256` | SHA-256 of that file's raw bytes, including comments and formatting. |
| `cbor_hex` | The full compiled validator's Concise Binary Object Representation (CBOR), in hex. Mandatory, not a hash. |
| `cbor_format` | `single_cbor_hex` or `double_cbor_hex`, matching the stored representation. |
| `plutus_version` | The compiled validator's Plutus version: `v1`, `v2`, or `v3`. |
| `parameterization_state` | The state of the validator's fixed parameters in the stored script. |
| `applied_parameters` | Applied parameter values as CBOR-hex strings, in application order. |
| `compiler_name` | Compiler name, when known. Optional. |
| `compiler_version` | Exact compiler version and build identifier, when known. Optional. |

The source commit, source-file checksum, and compiled CBOR are distinct values.
The checksum covers the named `.ak` file, not its imported files or the CBOR.
The commit anchors the repository snapshot.

## Parameter states

These fields describe fixed validator parameters, not datum, redeemer, or
transaction inputs.

| State | Meaning | `applied_parameters` |
| --- | --- | --- |
| `unparameterized` | The validator declares no fixed parameters. | `[]` |
| `unapplied` | Parameters exist, but none are applied to the stored script. | `[]` |
| `partially_applied` | Some fixed parameters are applied to the stored script. | Non-empty list. |
| `fully_applied` | All fixed parameters are applied to the stored script. | Non-empty list. |

Record only values already applied to the script represented by `cbor_hex`.
Do not select concrete parameter values merely to fill the metadata.

## Validation boundary

The schema checks field names, types, formats, and empty versus non-empty
parameter lists. It does not check that the upstream commit exists, recompute
the source checksum, decode the CBOR, or establish compilation or proof results.

Determining partial versus full application requires checking the selected
validator's declared parameters. Confirming that the proofs concern the recorded
script also requires evidence beyond this schema; the folder association alone
does not establish that result.

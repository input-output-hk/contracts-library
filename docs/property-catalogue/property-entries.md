# Property entries

Use the [property-entry schema](property.schema.json). This guide adds no fields
or categories.

## Authoring

Place `properties.json` in the relevant property-set folder under `formal/Formal/`,
alongside its Lean modules. It contains an array of property entries; see the
[Universal sample](../../formal/Formal/Universal/properties.json).

Each entry requires `id`, `title`, `category`, `summary`, and `theorems`.
The `id` identifies the property, not a validator. Give the property a descriptive
title and summarize what it asserts.

The `theorems` field lists fully qualified Lean theorem names. Use `[]` when none
are available; do not invent theorem names. No other entry fields are allowed.

Copy this draft template and replace its example values:

```json
[
  {
    "id": "replace-with-property-id",
    "title": "Replace with the property title",
    "category": "replace-with-category",
    "summary": "Replace with a precise statement of the property.",
    "theorems": []
  }
]
```

For a concrete validator snapshot, use the separate
[validator metadata guide](README.md). Do not add snapshot fields to an entry.

## Taxonomy

Use a non-empty category name describing the property's scope. The schema sets
no category values or defaults. These are examples, not an exhaustive list:

| Category | Scope |
| --- | --- |
| `universal` | Properties not specific to one validator, including blockchain-level properties. |
| `vesting-escrow` | Vesting and escrow properties. |
| `lending-cdp` | Lending and collateralized debt position properties. |
| `oracle` | Oracle properties. |
| `dex-amm-cross-script` | Decentralized exchange, automated market maker, and multi-script properties. |
| `stablecoin` | Stablecoin properties. |

## Checks

With Node.js 24 or newer, run from the repository root:

```sh
npm ci --ignore-scripts
npm run catalogue:check
npm run catalogue:test
```

The check validates both schemas and every `properties.json` and
`validator-metadata.json` under `formal/Formal/`. Tests include invalid inputs
and synthetic metadata, not real validator snapshots. These checks establish
structure only, not source provenance, CBOR correctness, or proof results.

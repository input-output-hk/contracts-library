# Property entries

Use the [property-entry schema](property.schema.json). This guide adds no fields
or categories.

## Authoring

Place `properties.json` in the relevant property-set folder under `formal/Formal/`,
alongside its Lean modules. It contains an array of property entries; see the
[Universal sample](../../formal/Formal/Universal/properties.json).

Each entry requires `id`, `title`, `category`, `status`, and `summary`.
The `id` identifies the property, not a validator. Give the property a descriptive
title and summarize what it asserts.

Optional fields: `spec_ref` references the specification, `theorems` lists fully
qualified Lean theorem names, and `open_targets` lists outstanding proof targets.
Omit unresolved optional references; do not invent specifications or theorem names.

Copy this draft template and replace its example values:

```json
[
  {
    "id": "replace-with-property-id",
    "title": "Replace with the property title",
    "category": "universal",
    "status": "draft",
    "summary": "Replace with a precise statement of the property."
  }
]
```

For a concrete validator snapshot, use the separate
[validator metadata guide](README.md). Do not add snapshot fields to an entry.

## Taxonomy

Choose the existing category that describes the property's scope:

| Category | Scope |
| --- | --- |
| `universal` | Properties not specific to one validator, including blockchain-level properties. |
| `vesting-escrow` | Vesting and escrow properties. |
| `lending-cdp` | Lending and collateralized debt position properties. |
| `oracle` | Oracle properties. |
| `dex-amm-cross-script` | Decentralized exchange, automated market maker, and multi-script properties. |
| `stablecoin` | Stablecoin properties. |

| Status | Meaning |
| --- | --- |
| `draft` | Proposed entry, not yet agreed. |
| `agreed` | Agreed entry. |
| `deprecated` | Entry no longer recommended for use. |

Status does not establish proof completeness or successful validation.

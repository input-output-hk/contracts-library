# Transaction-model bank

Each file in `Definitions/` contains a Lean context model and its metadata.
`Index.lean` imports the models and lists their metadata for legacy consumers.
The public command discovers each selected model's `runnable` export directly.
The runtime interface uses the pure purpose type in `Workflow.Types.Target`;
native context constructors keep their ledger input types.

```text
TxModels/
  README.md
  Index.lean
  Common.lean
  VestingTypes.lean
  Definitions/
    TxM001.lean
    ...
    TxM009.lean
```

| File | Contents |
| --- | --- |
| [Index.lean](Index.lean) | Legacy metadata index and `Index.toJson` export |
| [Common.lean](Common.lean) | Metadata fields, context assembly, and transaction builders |
| [VestingTypes.lean](VestingTypes.lean) | Types, encodings, and datum helpers for the experimental vesting models |
| [Runnable.lean](Runnable.lean) | Native builder, admission policy, and optional fixed script purpose |
| `Definitions/TxMNNN.lean` | One model implementation and its metadata |

The model IDs and constructors below belong to the `Formal.TxModels` namespace:

| ID | Constructor | Definition |
| --- | --- | --- |
| TxM-001 | `EveryMint.ctx` | [TxM001.lean](Definitions/TxM001.lean) |
| TxM-002 | `EveryWithdraw.ctx` | [TxM002.lean](Definitions/TxM002.lean) |
| TxM-003 | `EveryPublish.ctx` | [TxM003.lean](Definitions/TxM003.lean) |
| TxM-004 | `EveryVote.ctx` | [TxM004.lean](Definitions/TxM004.lean) |
| TxM-005 | `EveryPropose.ctx` | [TxM005.lean](Definitions/TxM005.lean) |
| TxM-006 | `EverySpend.ctx` | [TxM006.lean](Definitions/TxM006.lean) |
| TxM-007 | `TxM007.claim` | [TxM007.lean](Definitions/TxM007.lean) |
| TxM-008 | `TxM008.cancel` | [TxM008.lean](Definitions/TxM008.lean) |
| TxM-009 | `TxM009.spend` | [TxM009.lean](Definitions/TxM009.lean) |

Each model maintains four metadata fields: `id`, `title`, `plutus_version`, and
`description`. Its `metadata` declaration stays in the same file as its constructor.
The exported array follows [transaction-model.schema.json](transaction-model.schema.json).
Keep an existing ID's meaning stable; a changed model receives a new numbered ID.
`plutus_version` identifies the context format, not the full execution environment.

Models describe families of script contexts. A description explains fixed features,
variable values, and constructed relationships. The six open purpose models add
no ledger-validity premise. Claim and Cancel remain experimental baseline vesting
models; their constructor does not establish the property's validity premises.
Property/model combinations own the resulting check's limitations.

To add a runnable model, create its `Definitions/TxMNNN.lean` module with its
constructor, metadata, and one `runnable` export. Enable it by adding its ID to a
compatible property's `Run.lean` model list. Discovery supplies the imports and
binding. Update `Index.lean` when legacy metadata consumers also need the model.
The index does not infer compatibility or select executable code.

The six raw purpose models use `unparameterizedV3` admission and identify their
fixed purpose. UP-001 uses that purpose to skip declared handlers. Spending
schema requirements and pinned-artifact admission remain available for other models.

Use `Formal.TxModels.Index.toJson` when a JSON consumer needs the catalogue.
There is no separately authored model JSON list. The application checks the
exported records with its existing metadata reader; external schema policies for
required fields and list cardinality remain open.

TxM-009 models one script input with an inline `Constr 0 [B owner]` datum,
one key-recipient output containing input ADA minus the fee, a fixed
`Constr 0 []` redeemer, and one signer. Owner, signer, and recipient vary
independently. This native structural model is separate from the executable
reusable preparation path in `Workflow.Preparation.TxM009`; it does not imply ledger reachability.

[Requirements.lean](Requirements.lean) defines `DataShape.bytes`,
`DataShape.constr`, and `SpendingInputs`. `TxM009.inputs` declares its datum and
redeemer encodings independently of the four descriptive metadata fields. These
requirements describe every value the constructor can produce; compatibility
must not narrow that family to fit a validator schema. New models can declare
requirements in Lean and add a preparation binding without redesigning the
JavaScript or JSON catalogue.

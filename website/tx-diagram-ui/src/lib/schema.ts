import { z } from "zod";

export type Datum = { [key: string]: string | Datum };

export const DatumSchema: z.ZodType<Datum> = z.lazy(() =>
  z.record(z.string(), z.union([z.string(), DatumSchema])),
);

export const ValueSchema = z.record(z.string(), z.string());

export const DiagramUtxoSchema = z
  .strictObject({
    id: z.string().min(1).optional(),
    name: z.string(),
    address: z.string().optional(),
    value: ValueSchema.optional(),
    datum: DatumSchema.optional(),
    redeemer: z.string().optional(),
    reference: z.boolean().optional(),
    dots: z.boolean().optional(),
  })
  .refine((utxo) => !(utxo.dots && utxo.id), {
    path: ["id"],
    message: "An Omission Marker cannot have an id.",
  });

export const MintEntrySchema = z.strictObject({
  token: z.string(),
  amount: z.string(),
});

export const ValidRangeSchema = z.strictObject({
  lower: z.string().optional(),
  upper: z.string().optional(),
});

export const TransactionDiagramSchema = z.strictObject({
  name: z.string(),
  title: z.string(),
  inputs: z.array(DiagramUtxoSchema).default([]),
  outputs: z.array(DiagramUtxoSchema).default([]),
  mint: z.array(MintEntrySchema).default([]),
  signatures: z.array(z.string()).default([]),
  certificates: z.array(z.string()).default([]),
  withdrawals: z.array(z.string()).default([]),
  validRange: ValidRangeSchema.optional(),
  notes: z.string().optional(),
});

export const ChainTransactionSchema = z.strictObject({
  ...TransactionDiagramSchema.shape,
  block: z.string().optional(),
});

export const TransactionChainSchema = z
  .strictObject({
    name: z.string(),
    title: z.string(),
    transactions: z.array(ChainTransactionSchema).min(1),
    notes: z.string().optional(),
  })
  .superRefine((chain, ctx) => {
    const outputById = new Map<string, { txIndex: number; outputIndex: number }>();

    chain.transactions.forEach((transaction, txIndex) => {
      transaction.outputs.forEach((output, outputIndex) => {
        if (!output.id) {
          return;
        }
        const existing = outputById.get(output.id);
        if (existing) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "outputs", outputIndex, "id"],
            message: `Duplicate UTxO id "${output.id}".`,
          });
          return;
        }
        outputById.set(output.id, { txIndex, outputIndex });
      });
    });

    const consumerByOutput = new Map<string, { txIndex: number; inputIndex: number }>();
    const parentByTx = new Map<number, number>();

    chain.transactions.forEach((transaction, txIndex) => {
      let chainedInputs = 0;

      transaction.inputs.forEach((input, inputIndex) => {
        if (input.dots) {
          return;
        }

        if (input.reference) {
          if (input.id && !outputById.has(input.id)) {
            ctx.addIssue({
              code: "custom",
              path: ["transactions", txIndex, "inputs", inputIndex, "id"],
              message: `Unknown referenced UTxO id "${input.id}".`,
            });
          }
          return;
        }

        if (!input.id) {
          // An id-less spent input is ordinary funding, not a chain edge.
          return;
        }

        chainedInputs += 1;
        if (chainedInputs > 1) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "inputs", inputIndex],
            message: "A transaction can have at most one chained input.",
          });
        }

        if (input.address !== undefined || input.value !== undefined || input.datum !== undefined) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "inputs", inputIndex],
            message:
              "A chained input inherits its value, address and datum from the producer Output.",
          });
        }

        const output = outputById.get(input.id);
        if (!output) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "inputs", inputIndex, "id"],
            message: `Unknown chained UTxO id "${input.id}".`,
          });
          return;
        }

        const consumer = consumerByOutput.get(input.id);
        if (consumer) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "inputs", inputIndex, "id"],
            message: `UTxO "${input.id}" is already spent by another transaction.`,
          });
          return;
        }
        consumerByOutput.set(input.id, { txIndex, inputIndex });

        const parent = parentByTx.get(txIndex);
        if (parent !== undefined && parent !== output.txIndex) {
          ctx.addIssue({
            code: "custom",
            path: ["transactions", txIndex, "inputs", inputIndex],
            message: "A transaction can chain from only one parent.",
          });
          return;
        }
        parentByTx.set(txIndex, output.txIndex);
      });
    });

    const state = new Map<number, "visiting" | "done">();
    const visit = (txIndex: number): void => {
      const current = state.get(txIndex);
      if (current === "done") {
        return;
      }
      if (current === "visiting") {
        ctx.addIssue({
          code: "custom",
          path: ["transactions", txIndex],
          message: "Transaction chain contains a cycle.",
        });
        return;
      }
      state.set(txIndex, "visiting");
      const parent = parentByTx.get(txIndex);
      if (parent !== undefined) {
        visit(parent);
      }
      state.set(txIndex, "done");
    };

    chain.transactions.forEach((_transaction, txIndex) => {
      visit(txIndex);
    });
  });

export type DiagramUtxo = z.output<typeof DiagramUtxoSchema>;
export type DiagramUtxoInput = z.input<typeof DiagramUtxoSchema>;
export type MintEntry = z.output<typeof MintEntrySchema>;
export type MintEntryInput = z.input<typeof MintEntrySchema>;
export type ValidRange = z.output<typeof ValidRangeSchema>;
export type ValidRangeInput = z.input<typeof ValidRangeSchema>;
export type Value = z.output<typeof ValueSchema>;
export type TransactionDiagramInput = z.input<typeof TransactionDiagramSchema>;
export type TransactionDiagramData = z.output<typeof TransactionDiagramSchema>;
export type ChainTransaction = z.output<typeof ChainTransactionSchema>;
export type ChainTransactionInput = z.input<typeof ChainTransactionSchema>;
export type TransactionChainInput = z.input<typeof TransactionChainSchema>;
export type TransactionChainData = z.output<typeof TransactionChainSchema>;
export type TransactionDiagramProps = {
  transaction: TransactionDiagramData;
  title: string;
  element?: HTMLElement | undefined;
};
export type TransactionChainProps = {
  chain: TransactionChainData;
  title: string;
  element?: HTMLElement | undefined;
};

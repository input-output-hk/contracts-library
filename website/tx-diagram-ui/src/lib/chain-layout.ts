import type { ChainTransaction, DiagramUtxo, TransactionChainData } from "./schema.js";

export type ChainParent = {
  txIndex: number;
  inputIndex: number;
  outputId: string;
  outputIndex: number;
};

export type ChainOutputLocation = {
  txIndex: number;
  outputIndex: number;
  output: DiagramUtxo;
};

export type ChainLayoutEdge = {
  fromTxIndex: number;
  fromOutputIndex: number;
  toTxIndex: number;
  toInputIndex: number;
  redeemer: string | undefined;
};

export type ChainLayoutTransaction = {
  transaction: ChainTransaction;
  index: number;
  column: number;
  row: number;
};

export type ChainLayoutColumn = {
  label: string;
  transactions: ChainLayoutTransaction[];
};

export type ChainLayout = {
  columns: ChainLayoutColumn[];
  hasBlocks: boolean;
  edges: ChainLayoutEdge[];
  outputById: Map<string, ChainOutputLocation>;
  consumed: Set<string>;
  parents: Map<number, ChainParent>;
  columnByIndex: Map<number, number>;
};

export function needsChainLane(
  edge: ChainLayoutEdge,
  columnByIndex: ReadonlyMap<number, number>,
): boolean {
  const fromColumn = columnByIndex.get(edge.fromTxIndex);
  const toColumn = columnByIndex.get(edge.toTxIndex);
  return fromColumn === undefined || toColumn === undefined || toColumn - fromColumn !== 1;
}

export function computeChainLayout(chain: TransactionChainData): ChainLayout {
  const outputById = new Map<string, ChainOutputLocation>();

  chain.transactions.forEach((transaction, txIndex) => {
    transaction.outputs.forEach((output, outputIndex) => {
      if (output.id) {
        outputById.set(output.id, { txIndex, outputIndex, output });
      }
    });
  });

  const consumed = new Set<string>();
  const edges: ChainLayoutEdge[] = [];
  const parents = new Map<number, ChainParent>();

  chain.transactions.forEach((transaction, txIndex) => {
    let parent: ChainParent | undefined;

    transaction.inputs.forEach((input, inputIndex) => {
      if (input.dots || !input.id) {
        return;
      }
      const output = outputById.get(input.id);
      if (!output || input.reference) {
        return;
      }

      consumed.add(input.id);
      edges.push({
        fromTxIndex: output.txIndex,
        fromOutputIndex: output.outputIndex,
        toTxIndex: txIndex,
        toInputIndex: inputIndex,
        redeemer: input.redeemer,
      });

      if (!parent) {
        parent = {
          txIndex: output.txIndex,
          inputIndex,
          outputId: input.id,
          outputIndex: output.outputIndex,
        };
      }
    });

    if (parent) {
      parents.set(txIndex, parent);
    }
  });

  const depth = new Map<number, number>();
  const visiting = new Set<number>();
  const depthOf = (index: number): number => {
    const cached = depth.get(index);
    if (cached !== undefined) {
      return cached;
    }
    if (visiting.has(index)) {
      return 0;
    }
    visiting.add(index);
    const parent = parents.get(index);
    const value = parent ? depthOf(parent.txIndex) + 1 : 0;
    visiting.delete(index);
    depth.set(index, value);
    return value;
  };

  const hasBlocks = chain.transactions.some((transaction) => transaction.block !== undefined);
  const columns: ChainLayoutColumn[] = [];

  if (hasBlocks) {
    const byBlock = new Map<string, ChainLayoutTransaction[]>();

    chain.transactions.forEach((transaction, index) => {
      const key = transaction.block ?? "";
      const list = byBlock.get(key) ?? [];
      list.push({ transaction, index, column: 0, row: list.length });
      byBlock.set(key, list);
    });

    let columnIndex = 0;
    for (const [key, transactions] of byBlock) {
      for (const placed of transactions) {
        placed.column = columnIndex;
      }
      columns.push({ label: key || "No block", transactions });
      columnIndex += 1;
    }
  } else {
    const byDepth = new Map<number, ChainLayoutTransaction[]>();

    chain.transactions.forEach((transaction, index) => {
      const value = depthOf(index);
      const list = byDepth.get(value) ?? [];
      list.push({ transaction, index, column: value, row: list.length });
      byDepth.set(value, list);
    });

    const maxDepth = byDepth.size === 0 ? 0 : Math.max(...byDepth.keys());
    for (let value = 0; value <= maxDepth; value += 1) {
      const transactions = byDepth.get(value);
      if (transactions && transactions.length > 0) {
        columns.push({ label: `Step ${value + 1}`, transactions });
      }
    }
  }

  const columnByIndex = new Map<number, number>();
  columns.forEach((column, columnIndex) => {
    for (const placed of column.transactions) {
      columnByIndex.set(placed.index, columnIndex);
    }
  });

  return { columns, hasBlocks, edges, outputById, consumed, parents, columnByIndex };
}

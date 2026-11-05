/** The `data-chain-port` value on a consumed Output card. */
export function chainOutputPort(txIndex: number, outputIndex: number): string {
  return `out-${txIndex}-${outputIndex}`;
}

/** The `data-chain-port` value on the consumer's transaction box. */
export function chainTransactionPort(txIndex: number): string {
  return `tx-${txIndex}`;
}

/** The `data-chain-port` value on a consumer's extra-input group. */
export function chainInputsPort(txIndex: number): string {
  return `inputs-${txIndex}`;
}

/** Selector for a chain port on the chain content element. */
export function chainPortSelector(port: string): string {
  return `[data-chain-port="${port}"]`;
}

/** Selector for a transaction card inside the chain content element. */
export function chainCardSelector(txIndex: number): string {
  return `[data-chain-card="${txIndex}"]`;
}

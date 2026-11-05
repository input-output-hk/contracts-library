const MAX_VISIBLE_LENGTH = 18;

/** Keep full ids in the tooltip while stopping long hashes from widening a card. */
export function formatUtxoId(id: string): string {
  if (id.length <= MAX_VISIBLE_LENGTH) {
    return id;
  }
  return `${id.slice(0, 8)}…${id.slice(-6)}`;
}

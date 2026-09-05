/**
 * Shared types and functions used across multiple contracts.
 */

import {
  mConStr0,
  mConStr1,
  resolveDataHash,
  unixTimeToEnclosingSlot,
  type Data,
  type SlotConfig,
  type TxInput,
} from "@meshsdk/core";

/**
 * A beneficiary credential. A `key` credential authorizes by signing;
 * a `script` credential authorizes by being invoked (withdraw-0).
 * Hashes are hex strings (Blake2b-224, 28 bytes / 56 hex chars).
 */
export type Credential =
  | { kind: "key"; hash: string }
  | { kind: "script"; hash: string };

/** Encode a Credential to CBOR Data (mirrors Aiken's flat format). */
export function credentialToData(c: Credential): Data {
  return c.kind === "key" ? mConStr0([c.hash]) : mConStr1([c.hash]);
}

/** The amount of lovelace in 1 ADA. */
export const ADA = 1_000_000n;

/**
 * The unique NFT name an on-chain script derives from a consumed output
 * reference: `blake2b_256(serialise_data(ref))`. Mirrors `nft_name_from_ref`
 * in `onchain/lib/dao/utils.ak`.
 */
export function nftNameFromRef(ref: TxInput): string {
  return resolveDataHash(mConStr0([ref.txHash, ref.outputIndex]));
}

/** The enclosing slot and its start time (POSIX ms) for a wall-clock instant. */
export interface SlotBound {
  slot: number;
  startMs: number;
}

/**
 * Convert a POSIX-milliseconds instant into the enclosing slot and that slot's
 * start time, using the given slot config. A validator reading
 * `validity_range.lower_bound` after `.invalidBefore(slot)` sees exactly
 * `startMs`, so datum fields that must equal "now" should use `startMs`.
 */
export function enclosingSlotBound(
  nowMs: number,
  slotConfig: SlotConfig,
): SlotBound {
  const slot = unixTimeToEnclosingSlot(nowMs, slotConfig);
  const startMs =
    slotConfig.zeroTime + (slot - slotConfig.zeroSlot) * slotConfig.slotLength;
  return { slot, startMs };
}

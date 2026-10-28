/**
 * Shared types and functions used across multiple contracts.
 */

import {
  type Data,
  type MeshTxBuilder,
  mConStr0,
  mConStr1,
  resolveDataHash,
  SLOT_CONFIG_NETWORK,
  type SlotConfig,
  type TxInput,
  type UTxO,
  unixTimeToEnclosingSlot,
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

/** The networks every builder accepts. */
export type Network = "mainnet" | "preprod" | "preview";

/**
 * `mainnet` is network id 1; every devnet (and Mesh's legacy "testnet") is 0.
 * Accepts Mesh's wider `Network` union so builders typed against it can call
 * this without casts.
 */
export function networkIdOf(network: Network | "testnet"): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

/** The enclosing slot + start time for `now` on the given network/devnet. */
export function slotBound(
  network: Network,
  now: number,
  customSlotConfig?: SlotConfig,
) {
  return enclosingSlotBound(
    now,
    customSlotConfig ?? SLOT_CONFIG_NETWORK[network],
  );
}

/** The NFT token name held by `utxo` under `policyId`, or "" if none. */
export function nftNameOf(utxo: UTxO, policyId: string): string {
  const unit = utxo.output.amount
    .map((a) => a.unit)
    .find((u) => u !== "lovelace" && u.startsWith(policyId));
  return unit ? unit.slice(policyId.length) : "";
}

/** Builder options shared by every transaction's closing calls. */
export interface FinalizeOptions {
  collateral: UTxO;
  changeAddress: string;
  utxos: UTxO[];
}

/**
 * The closing chain every builder ends with: collateral + change + selection
 * + completion, returning the unsigned transaction hex.
 */
export async function finalizeTx(
  txBuilder: MeshTxBuilder,
  o: FinalizeOptions,
): Promise<string> {
  return txBuilder
    .txInCollateral(
      o.collateral.input.txHash,
      o.collateral.input.outputIndex,
      o.collateral.output.amount,
      o.collateral.output.address,
    )
    .changeAddress(o.changeAddress)
    .selectUtxosFrom(o.utxos)
    .complete();
}

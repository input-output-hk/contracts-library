/**
 * Datum/redeemer encoding and the vesting schedule math.
 *
 * The CBOR constructor layout MUST match the Aiken blueprint exactly:
 *   Credential   = Constr 0 [vkh]  (key)  |  Constr 1 [scripthash]  (script)
 *   VestedAsset  = Constr 0 [policyId, assetName, total]
 *   VestingDatum = Constr 0 [beneficiary, locker, [VestedAsset], startTime, endTime, recoveryTime]
 *   Claim        = Constr 0 []
 *   Cancel       = Constr 1 []
 */

import { mConStr0, mConStr1, type Data } from "@meshsdk/core";
import { credentialToData } from "../common";
import type { VestedAsset, VestingDatum } from "./types";

export { credentialToData };

export function vestedAssetToData(a: VestedAsset): Data {
  return mConStr0([a.policyId, a.assetName, a.total]);
}

export function vestingDatumToData(d: VestingDatum): Data {
  return mConStr0([
    credentialToData(d.beneficiary),
    credentialToData(d.locker),
    d.vesting.map(vestedAssetToData),
    d.startTime,
    d.endTime,
    d.recoveryTime,
  ]);
}

/** The `Claim` redeemer (beneficiary withdraws the vested portion). */
export function claimRedeemer(): Data {
  return mConStr0([]);
}

/** The `Cancel` redeemer (locker recovers the remainder after recoveryTime). */
export function cancelRedeemer(): Data {
  return mConStr1([]);
}

/**
 * Quantity of an asset vested by `now`, mirroring `vested_quantity` in
 * `onchain/lib/vesting/linear.ak`. Floored via BigInt division, non-decreasing
 * in `now`. All times in POSIX milliseconds. Caller guarantees `start < end`.
 */
export function vestedQuantity(
  total: bigint,
  start: number,
  end: number,
  now: number,
): bigint {
  if (now <= start) return 0n;
  if (now >= end) return total;
  return (total * BigInt(now - start)) / BigInt(end - start);
}

/**
 * For each asset in the bundle, the quantity that must REMAIN locked in the
 * continuing output at time `now`: `total - vested(now)`. Entries that reach
 * zero are dropped. Returns [] when fully vested (no continuing output needed).
 */
export function requiredRemainder(
  datum: VestingDatum,
  now: number,
): VestedAsset[] {
  return datum.vesting
    .map((a) => ({
      ...a,
      total:
        a.total - vestedQuantity(a.total, datum.startTime, datum.endTime, now),
    }))
    .filter((a) => a.total > 0n);
}

/** Byte-wise order on `(policyId, assetName)`, matching the on-chain check. */
function compareAssetKey(a: VestedAsset, b: VestedAsset): number {
  const cmp = (x: string, y: string) => {
    const [l, r] = [x.toLowerCase(), y.toLowerCase()];
    return l < r ? -1 : l > r ? 1 : 0;
  };
  return cmp(a.policyId, b.policyId) || cmp(a.assetName, b.assetName);
}

/**
 * Returns a copy of `vesting` sorted into the order the validator requires
 * (byte-wise by policy id, then asset name; ada first). Does not merge
 * duplicates: `assertValidBundle` still rejects them.
 */
export function sortVestingBundle(vesting: VestedAsset[]): VestedAsset[] {
  return [...vesting].sort(compareAssetKey);
}

/**
 * Throws unless `vesting` is well-formed (spec §3.1): keys strictly ascending
 * (so no asset appears twice) and every total non-negative. A bundle that
 * breaks this can never be claimed; only the locker can recover it after
 * `recoveryTime`.
 */
export function assertValidBundle(vesting: VestedAsset[]): void {
  vesting.forEach((a, i) => {
    if (a.total < 0n) {
      throw new Error(`Invalid vesting bundle: negative total at index ${i}`);
    }
    if (i > 0 && compareAssetKey(vesting[i - 1], a) >= 0) {
      throw new Error(
        `Invalid vesting bundle: entries must be strictly ascending by (policyId, assetName) with no duplicates (index ${i}); use sortVestingBundle`,
      );
    }
  });
}

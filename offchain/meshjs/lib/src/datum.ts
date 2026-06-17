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
import type { Credential, VestedAsset, VestingDatum } from "./types";

export function credentialToData(c: Credential): Data {
  // bytes are passed as hex strings in Mesh's Data representation
  return c.kind === "key" ? mConStr0([c.hash]) : mConStr1([c.hash]);
}

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

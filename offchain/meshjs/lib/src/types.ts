/**
 * Off-chain mirror of the on-chain types in `onchain/lib/vesting/types.ak`.
 * See specs/vesting/linear-vesting.md §3.
 */

/**
 * A beneficiary credential. A `key` credential authorizes a claim by signing;
 * a `script` credential authorizes by being invoked (withdraw-0) in the claim
 * transaction. Hashes are hex strings (Blake2b-224, 28 bytes / 56 hex chars).
 */
export type Credential =
    | { kind: "key"; hash: string }
    | { kind: "script"; hash: string };

/**
 * One asset in the vesting bundle with its ORIGINAL total quantity. ada is the
 * entry with empty `policyId` and empty `assetName`.
 */
export interface VestedAsset {
    /** Policy id (hex), or "" for ada. */
    policyId: string;
    /** Asset name (hex), or "" for ada. */
    assetName: string;
    /** Original total quantity vested over the schedule. */
    total: bigint;
}

/** Immutable vesting state. Times are POSIX time in MILLISECONDS. */
export interface VestingDatum {
    /** Who can claim after `startTime`. */
    beneficiary: Credential;
    /** Who may recover the remainder after `recoveryTime`. */
    locker: Credential;
    /** Assets locked initially */
    vesting: VestedAsset[];
    /** POSIX time where `beneficiary` can start claiming */
    startTime: number;
    /** POSIX time where `beneficiary` can claim the whole `vesting` */
    endTime: number;
    /** After this time the locker may recover whatever remains. Must be > endTime. */
    recoveryTime: number;
}

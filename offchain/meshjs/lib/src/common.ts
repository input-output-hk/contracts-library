/**
 * Shared types and functions used across multiple contracts.
 */

import { mConStr0, mConStr1, type Data } from "@meshsdk/core";

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

/** A reference to a transaction output. */
export interface OutputRef {
  transactionId: string;
  outputIndex: number;
}

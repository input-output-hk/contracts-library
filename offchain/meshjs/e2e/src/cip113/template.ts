/**
 * The `IssuanceCborHex` registration template.
 *
 * The registry reconstructs the minting policy as
 * `blake2b_224(0x03 || prefix || hashed_param || postfix)` and requires it to
 * equal the registered policy id (`apply_hashed_parameter`). `prefix`/`postfix`
 * are the applied `issuance_mint` flat program split around the 28-byte
 * minting-logic script hash — the split is definitionally the applied program,
 * so the derived policy id is the applied script's ledger hash.
 */

import { applyParamsToScript, mConStr1 } from "@meshsdk/core";

import { stripCborWrappers } from "./core";

export interface IssuanceTemplate {
  prefix: string;
  postfix: string;
}

/**
 * Derive the template from the vendored `issuance_mint` code, applying the
 * minting-logic credential and the protocol-params policy exactly as the
 * deployed policy does.
 */
export function issuanceTemplate(
  issuanceMintCode: string,
  mintingLogicHash: string,
  paramsPolicy: string,
): IssuanceTemplate {
  const applied = applyParamsToScript(
    issuanceMintCode,
    [mConStr1([mintingLogicHash]), paramsPolicy],
    "Mesh",
  ) as string;
  const flat = stripCborWrappers(applied);

  // The minting-logic credential is embedded as `Constr 1 [ bytes(28) ]`:
  // `d87a 9f 581c <hash> ff`. Split around the hash.
  const anchor = "d87a9f581c" + mintingLogicHash;
  const at = flat.indexOf(anchor);
  if (at === -1) {
    throw new Error("issuance_mint: minting-logic credential not found in applied program");
  }
  const hashStart = at + "d87a9f581c".length;
  const hashEnd = hashStart + mintingLogicHash.length;
  if (flat.slice(hashEnd, hashEnd + 2) !== "ff") {
    throw new Error("issuance_mint: unexpected credential framing");
  }

  const prefix = flat.slice(0, hashStart);
  const postfix = flat.slice(hashEnd);
  // Sanity: the split reconstructs the applied program exactly.
  if (prefix + mintingLogicHash + postfix !== flat) {
    throw new Error("issuance_mint: template split does not reconstruct the program");
  }
  return { prefix, postfix };
}

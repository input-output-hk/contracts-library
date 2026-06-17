/**
 * Off-chain side of the pluggable authorization in
 * `onchain/lib/authorization.ak`. An action is authorized by satisfying a
 * `Credential`:
 *
 *   - a **key** credential  → a required signer (the library adds it for you);
 *   - a **script** credential → the approving script is invoked via a
 *     withdraw-0 in the same transaction. You describe that script with a
 *     `ScriptAuthorizer`; the library checks its hash matches the credential,
 *     derives the reward address, and wires the withdrawal in.
 *
 * This lives apart from the vesting builders on purpose: every contract in the
 * library reuses the same authorization interface (ARCHITECTURE.md §3). Adding
 * support for a new authorization scheme (multisig, DAO, smart wallet) needs no
 * library change — you just pass its script and redeemer.
 */

import {
  mConStr0,
  resolveScriptHash,
  serializeRewardAddress,
  type Data,
  type MeshTxBuilder,
  type UTxO,
} from "@meshsdk/core";

import type { Credential } from "./types";

export type PlutusVersion = "V1" | "V2" | "V3";

/**
 * How to satisfy a **script** credential: invoke its approving script as a
 * withdraw-0. Provide the script either inline (`scriptCbor`) or by reference
 * (`reference`). For the common case you only need `{ scriptCbor, redeemer }`.
 */
export interface ScriptAuthorizer {
  /** The approving script, inlined (hex). Provide this OR `reference`. */
  scriptCbor?: string;
  /** Or an on-chain UTxO carrying the approving script as a reference script. */
  reference?: UTxO;
  /**
   * Script hash. Computed from `scriptCbor` when omitted; required alongside
   * `reference` if the reference UTxO does not carry one.
   */
  scriptHash?: string;
  /** Redeemer the approving script expects. Defaults to unit (`Constr 0 []`). */
  redeemer?: Data;
  /** Plutus version of the approving script. Default `"V3"`. */
  version?: PlutusVersion;
  /**
   * Escape hatch: you already attached the authorizer to the `txBuilder`
   * yourself, so the library wires nothing. For genuinely custom invocations.
   */
  manual?: boolean;
}

const UNIT: Data = mConStr0([]);

/**
 * Apply the authorization for `credential` to `txBuilder`.
 *
 * - Key credential: adds the required signer (`authorizer` is ignored).
 * - Script credential: attaches the withdraw-0 described by `authorizer`,
 *   after verifying the script hash matches the credential.
 *
 * Throws early (before any building) on a missing or mismatched authorizer, so
 * mistakes surface as a clear error rather than an unsatisfiable transaction.
 */
export function applyAuthorization(
  txBuilder: MeshTxBuilder,
  credential: Credential,
  authorizer: ScriptAuthorizer | undefined,
  networkId: 0 | 1,
): void {
  if (credential.kind === "key") {
    txBuilder.requiredSignerHash(credential.hash);
    return;
  }

  if (!authorizer) {
    throw new Error(
      "This credential is a script, so it must be authorized by invoking its " +
        "approving script. Pass `authorizer: { scriptCbor, redeemer }` (or " +
        "`{ manual: true }` if you attached the withdrawal to the txBuilder " +
        "yourself).",
    );
  }
  if (authorizer.manual) return;

  const version = authorizer.version ?? "V3";

  const hash =
    authorizer.scriptHash ??
    (authorizer.scriptCbor !== undefined
      ? resolveScriptHash(authorizer.scriptCbor, version)
      : authorizer.reference?.output.scriptHash);
  if (hash === undefined) {
    throw new Error(
      "Cannot determine the authorizer script hash: provide `scriptCbor`, or " +
        "`scriptHash` alongside `reference`.",
    );
  }
  if (hash !== credential.hash) {
    throw new Error(
      `Authorizer script hash (${hash}) does not match the credential in the ` +
        `datum (${credential.hash}).`,
    );
  }

  const rewardAddress = serializeRewardAddress(hash, true, networkId);

  withdrawalScriptVersion(txBuilder, version).withdrawal(rewardAddress, "0");
  if (authorizer.scriptCbor !== undefined) {
    txBuilder.withdrawalScript(authorizer.scriptCbor);
  } else if (authorizer.reference !== undefined) {
    txBuilder.withdrawalTxInReference(
      authorizer.reference.input.txHash,
      authorizer.reference.input.outputIndex,
      undefined,
      hash,
    );
  } else {
    throw new Error(
      "`authorizer` needs one of `scriptCbor`, `reference`, or `manual: true`.",
    );
  }
  txBuilder.withdrawalRedeemerValue(authorizer.redeemer ?? UNIT);
}

function withdrawalScriptVersion(
  txBuilder: MeshTxBuilder,
  version: PlutusVersion,
): MeshTxBuilder {
  if (version === "V1") return txBuilder.withdrawalPlutusScriptV1();
  if (version === "V2") return txBuilder.withdrawalPlutusScriptV2();
  return txBuilder.withdrawalPlutusScriptV3();
}

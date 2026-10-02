/**
 * Test-only CIP-113 core helpers for the event-triggered assets tx3 e2e.
 *
 * The tx3 protocol cannot apply parameters to scripts, so the applied core and
 * module scripts are computed here with the vendored blueprints and handed to
 * the protocol through its environment. Both the vendored e2e helpers and the
 * library builders return `applyParamsToScript`'s double-CBOR form; tx3 hashes
 * the exact bytes it is handed and the Plutus evaluator CBOR-decodes them, so
 * every script handed over is reduced to its single-CBOR payload with
 * `unwrapCborBytes`.
 */

import {
  pubKeyAddress,
  scriptAddress,
  serializeAddressObj,
  type PlutusScript,
} from "@meshsdk/core";

import {
  credentialToData,
  issuanceScript,
  nativeMintPolicyScript,
  scriptHashOf as meshScriptHashOf,
  thirdPartyScript,
  transferScript,
  transformationScript,
  type Credential,
  type Schedule,
} from "@contracts-library/meshjs";

import { issuanceMintCompiledCode } from "../../../meshjs/e2e/src/cip113/blueprint";
import {
  applyScript,
  scriptHashOf,
  stripCborWrappers,
} from "../../../meshjs/e2e/src/cip113/core";
import {
  applyCoreScripts,
  type CoreConfig,
  type CoreScripts,
} from "../../../meshjs/e2e/src/cip113/scripts";
import { issuanceTemplate } from "../../../meshjs/e2e/src/cip113/template";

export {
  applyCoreScripts,
  applyScript,
  issuanceMintCompiledCode,
  issuanceTemplate,
  scriptHashOf,
  stripCborWrappers,
};
export type { CoreConfig, CoreScripts };

export const NETWORK_ID = 0;

export const bytes = (value: string): Uint8Array =>
  Uint8Array.from(Buffer.from(value, "hex"));
export const hexOf = (value: Uint8Array): string =>
  Buffer.from(value).toString("hex");

export const refParts = (
  ref: string,
): { txHash: string; outputIndex: number } => {
  const [txHash, outputIndex] = ref.split("#");
  return { txHash, outputIndex: Number(outputIndex) };
};

/** `txHash#index` refs in the ledger's canonical order (txHash, index). */
export function sortRefs(refs: string[]): string[] {
  return [...refs].sort((a, b) => {
    const [ah, ai] = a.split("#");
    const [bh, bi] = b.split("#");
    const x = ah.toLowerCase();
    const y = bh.toLowerCase();
    if (x !== y) return x < y ? -1 : 1;
    return Number(ai) - Number(bi);
  });
}

export function refIndexOf(refs: string[], target: string): number {
  const index = sortRefs(refs).indexOf(target);
  if (index < 0) throw new Error(`reference input ${target} not in set`);
  return index;
}

/**
 * Withdrawals are ordered by the ledger with every script credential before
 * every verification key, bytewise within each group. Every withdrawal in this
 * suite is a script credential, so a plain bytewise sort is the ledger order.
 */
export function withdrawalIndexOf(hashes: string[], target: string): number {
  const index = [...hashes]
    .map((h) => h.toLowerCase())
    .sort()
    .indexOf(target.toLowerCase());
  if (index < 0) throw new Error(`withdrawal ${target} not in set`);
  return index;
}

// ------------------------------------------------------------------ addresses

/** Enterprise script address (payment credential only). */
export function scriptAddr(hash: string): string {
  return serializeAddressObj(scriptAddress(hash), NETWORK_ID);
}

/** PLB-custodied base address: script payment + owner stake credential. */
export function plbAddr(
  plbHash: string,
  stakeHash: string,
  stakeIsScript: boolean,
): string {
  return serializeAddressObj(
    scriptAddress(plbHash, stakeHash, stakeIsScript),
    NETWORK_ID,
  );
}

/** Base address with key payment and key stake. */
export function baseAddr(paymentHash: string, stakeHash: string): string {
  return serializeAddressObj(pubKeyAddress(paymentHash, stakeHash), NETWORK_ID);
}

/** Hex bytes of a script's reward (stake) address, for tx3 `Bytes` env. */
export const rewardAddrHex = (hash: string): string => `f0${hash}`;

// --------------------------------------------------------------- bond scripts

export interface BondParams {
  registryNodeCs: string;
  paramsPolicy: string;
  issuer: Credential;
  principalName: string;
  referenceName: string;
  schedule: Schedule;
  scale: number;
}

export interface BondScripts {
  issuance: PlutusScript;
  issuanceMint: PlutusScript;
  cipPolicy: string;
  transfer: PlutusScript;
  thirdParty: PlutusScript;
  transformation: PlutusScript;
  nativeMint: PlutusScript;
  nativePolicy: string;
  finalDeadline: number;
}

/** Apply the module scripts and the core `issuance_mint` for one bond. */
export function bondScripts(p: BondParams): BondScripts {
  const finalDeadline = p.schedule[p.schedule.length - 1].deadline;

  const transfer = transferScript({
    registryNodeCs: p.registryNodeCs,
    finalDeadline,
  });
  const thirdParty = thirdPartyScript({
    registryNodeCs: p.registryNodeCs,
    finalDeadline,
  });
  const transformation = transformationScript({
    referenceName: p.referenceName,
    schedule: p.schedule,
  });

  const issuance = issuanceScript({
    registryNodeCs: p.registryNodeCs,
    issuer: p.issuer,
    transferLogic: meshScriptHashOf(transfer),
    thirdPartyLogic: meshScriptHashOf(thirdParty),
    transformationScript: meshScriptHashOf(transformation),
    principalName: p.principalName,
    referenceName: p.referenceName,
    schedule: p.schedule,
    scale: p.scale,
  });

  const issuanceMint = applyScript(issuanceMintCompiledCode, [
    credentialToData({ kind: "script", hash: meshScriptHashOf(issuance) }),
    p.paramsPolicy,
  ]);
  const cipPolicy = scriptHashOf(issuanceMint);

  const nativeMint = nativeMintPolicyScript({
    cipPolicy,
    principalName: p.principalName,
    scale: p.scale,
    schedule: p.schedule,
  });

  return {
    issuance,
    issuanceMint,
    cipPolicy,
    transfer,
    thirdParty,
    transformation,
    nativeMint,
    nativePolicy: meshScriptHashOf(nativeMint),
    finalDeadline,
  };
}

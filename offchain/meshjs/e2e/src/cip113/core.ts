/**
 * CIP-113 core offchain helpers: parameter application, hashes, addresses and
 * the ledger's index-ordering rules.
 *
 * Framing note: `applyParamsToScript` double-CBOR-wraps. MeshJS takes
 * `script.code` verbatim as the script witness/reference content, so the
 * double-CBOR form is the one that puts the single-CBOR payload (what the
 * Plutus evaluator decodes and the ledger hashes) on chain; `resolveScriptHash`
 * unwraps the same way. Keep this aligned with the library's `event_triggered`
 * builders.
 */

import {
  applyParamsToScript,
  resolveScriptHash,
  scriptAddress,
  serializeAddressObj,
  serializeRewardAddress,
  type Data,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import { plutusVersion } from "./blueprint";

/** Strip every CBOR bytestring wrapper (`58xx`/`59xxxx`) to the flat program. */
export function stripCborWrappers(hex: string): string {
  let h = hex;
  for (;;) {
    const tag = h.slice(0, 2);
    if (tag === "59") {
      h = h.slice(6, 6 + parseInt(h.slice(2, 6), 16) * 2);
    } else if (tag === "58") {
      h = h.slice(4, 4 + parseInt(h.slice(2, 4), 16) * 2);
    } else {
      break;
    }
  }
  return h;
}

/** Strip a single CBOR bytestring wrapper (the double-CBOR -> single-CBOR step). */
export function unwrapCborBytes(hex: string): string {
  const tag = Number.parseInt(hex.slice(0, 2), 16);
  const headerHexLen =
    tag === 0x58 ? 4 : tag === 0x59 ? 6 : tag === 0x5a ? 10 : 0;
  return hex.slice(headerHexLen);
}

/**
 * Apply parameters, returning `applyParamsToScript`'s double-CBOR form —
 * the form MeshJS expects for `script.code`.
 */
export function applyScript(code: string, params: Data[]): PlutusScript {
  const applied = applyParamsToScript(code, params, "Mesh") as string;
  return { code: applied, version: plutusVersion };
}

/** Ledger script hash (policy id / stake credential) of an applied script. */
export function scriptHashOf(script: PlutusScript): string {
  return resolveScriptHash(script.code, script.version);
}

/** Reward address of a script stake credential (for its withdraw-0). */
export function rewardAddressOf(hash: string, networkId: 0 | 1): string {
  return serializeRewardAddress(hash, true, networkId);
}

/** A script-address (optionally with a stake credential). */
export function scriptAddressOf(
  paymentHash: string,
  networkId: 0 | 1,
  stake?: { hash: string; isScript: boolean },
): string {
  return serializeAddressObj(
    scriptAddress(paymentHash, stake?.hash, stake?.isScript ?? false),
    networkId,
  );
}

// ------------------------------------------------------ ledger index ordering

/** Canonical `reference_inputs` order: sorted by (txHash, outputIndex). */
export function sortReferenceInputs(inputs: UTxO[]): UTxO[] {
  return [...inputs].sort((a, b) => {
    const ha = a.input.txHash.toLowerCase();
    const hb = b.input.txHash.toLowerCase();
    if (ha !== hb) return ha < hb ? -1 : 1;
    return a.input.outputIndex - b.input.outputIndex;
  });
}

/** Index of `target` in the canonically-sorted reference-input set. */
export function referenceIndexOf(sorted: UTxO[], target: UTxO): number {
  const i = sorted.findIndex(
    (u) =>
      u.input.txHash === target.input.txHash &&
      u.input.outputIndex === target.input.outputIndex,
  );
  if (i === -1)
    throw new Error(
      `reference input ${target.input.txHash}#${target.input.outputIndex} not in set`,
    );
  return i;
}

export interface WithdrawalKey {
  hash: string;
  isScript: boolean;
}

/**
 * Ledger withdrawal order: every `Script` credential before every
 * `VerificationKey` credential, bytewise within each group.
 */
export function compareWithdrawalKeys(
  a: WithdrawalKey,
  b: WithdrawalKey,
): number {
  if (a.isScript !== b.isScript) return a.isScript ? -1 : 1;
  const ha = a.hash.toLowerCase();
  const hb = b.hash.toLowerCase();
  return ha < hb ? -1 : ha > hb ? 1 : 0;
}

/** Index of a withdrawal in the ledger-ordered complete withdrawal set. */
export function withdrawalIndexOf(
  all: WithdrawalKey[],
  target: WithdrawalKey,
): number {
  const sorted = [...all].sort(compareWithdrawalKeys);
  const i = sorted.findIndex(
    (w) =>
      w.isScript === target.isScript &&
      w.hash.toLowerCase() === target.hash.toLowerCase(),
  );
  if (i === -1) throw new Error(`withdrawal ${target.hash} not in the set`);
  return i;
}

/**
 * Explicit per-redeemer execution budget for the e2e builders. Every CIP-113
 * script here evaluates far below this (the heaviest observed is ~0.6M mem),
 * and keeping each budget bounded keeps multi-script transactions under the
 * 14M per-tx limit.
 */
export const EX_UNITS = { mem: 1_500_000, steps: 700_000_000 };

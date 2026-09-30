/**
 * Encoders for the CIP-113 core datums/redeemers, matching
 * `cip113-programmable-tokens/lib/types.ak` (constructor order matters).
 */

import { mConStr, mConStr0, mConStr1, mConStr2, type Data } from "@meshsdk/core";

import {
  credentialToData,
  registryNodeToData,
  type Credential,
  type RegistryNode,
} from "@contracts-library/meshjs";

export { credentialToData, registryNodeToData };
export type { Credential, RegistryNode };

// ------------------------------------------------------------- protocol params

export interface ProtocolParams {
  programmableLogicGlobalCred: Credential;
  issuanceLogicCred: Credential;
  transferCred: Credential;
  thirdPartyCred: Credential;
  upgradeCred: Credential;
  pendingUpgradeCred: Credential | null;
}

export function protocolParamsToData(p: ProtocolParams): Data {
  return mConStr0([
    credentialToData(p.programmableLogicGlobalCred),
    credentialToData(p.issuanceLogicCred),
    credentialToData(p.transferCred),
    credentialToData(p.thirdPartyCred),
    credentialToData(p.upgradeCred),
    p.pendingUpgradeCred === null
      ? mConStr1([])
      : mConStr0([credentialToData(p.pendingUpgradeCred)]),
  ]);
}

/** `IssuanceCborHex { prefix_cbor_hex, postfix_cbor_hex }`. */
export function issuanceCborHexToData(prefix: string, postfix: string): Data {
  return mConStr0([prefix, postfix]);
}

// ------------------------------------------------------- upgrade multisig tree

/**
 * `MultisigScript` (lib/multisig.ak) — the upgrade authority's approval tree.
 * Constructor order: Signature 0, AllOf 1, AnyOf 2, AtLeast 3, Before 4,
 * After 5, Script 6.
 */
export type MultisigScript =
  | { kind: "signature"; keyHash: string }
  | { kind: "allOf"; scripts: MultisigScript[] }
  | { kind: "anyOf"; scripts: MultisigScript[] }
  | { kind: "atLeast"; required: number; scripts: MultisigScript[] }
  | { kind: "before"; time: number }
  | { kind: "after"; time: number }
  | { kind: "script"; scriptHash: string };

export function multisigToData(s: MultisigScript): Data {
  switch (s.kind) {
    case "signature":
      return mConStr(0, [s.keyHash]);
    case "allOf":
      return mConStr(1, [s.scripts.map(multisigToData)]);
    case "anyOf":
      return mConStr(2, [s.scripts.map(multisigToData)]);
    case "atLeast":
      return mConStr(3, [s.required, s.scripts.map(multisigToData)]);
    case "before":
      return mConStr(4, [s.time]);
    case "after":
      return mConStr(5, [s.time]);
    case "script":
      return mConStr(6, [s.scriptHash]);
  }
}

export function multisigSignature(keyHash: string): MultisigScript {
  return { kind: "signature", keyHash };
}

// ----------------------------------------------------------------- redeemers

export function registryInitRedeemer(): Data {
  return mConStr0([]);
}

export function registryInsertRedeemer(
  key: string,
  mintingLogic: Credential,
): Data {
  return mConStr1([key, credentialToData(mintingLogic)]);
}

/** `BaseSpendRedeemer { params_idx, wdrl_idx }`. */
export function baseSpendRedeemer(paramsIdx: number, wdrlIdx: number): Data {
  return mConStr0([paramsIdx, wdrlIdx]);
}

/** Dispatcher arms: TransferAct = 0, ThirdPartyAct = 1, UnfrackingAct = 2. */
export function transferAct(): Data {
  return mConStr0([]);
}

export function thirdPartyAct(): Data {
  return mConStr1([]);
}

export function unfrackingAct(): Data {
  return mConStr2([]);
}

/** `RegistryProof`: TokenExists { node_idx } = 0, TokenDoesNotExist = 1. */
export interface RegistryProof {
  nodeIdx: number;
}

export function transferRedeemer(proofs: RegistryProof[]): Data {
  return mConStr0([proofs.map((p) => mConStr0([p.nodeIdx]))]);
}

/** `ThirdPartyRedeemer { registry_node_idx, outputs_start_idx }`. */
export function thirdPartyRedeemer(
  registryNodeIdx: number,
  outputsStartIdx: number,
): Data {
  return mConStr0([registryNodeIdx, outputsStartIdx]);
}

/** `IssuanceMintRedeemer { params_idx }`. */
export function issuanceMintRedeemer(paramsIdx: number): Data {
  return mConStr0([paramsIdx]);
}

/**
 * `IssuanceLogicRedeemer = Pairs<PolicyId, MintingRegistryProof>` — a Plutus
 * MAP. `MintingRegistryProof`: RefInput { index } = 0, OutputIndex { index } = 1.
 */
export function issuanceLogicRedeemer(
  entries: { policy: string; index: number }[],
): Data {
  return new Map(
    entries.map((e) => [e.policy, mConStr1([e.index])] as [string, Data]),
  );
}

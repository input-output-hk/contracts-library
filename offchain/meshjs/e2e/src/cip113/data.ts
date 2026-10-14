/**
 * Deploy-only encoders for the CIP-113 core (protocol params, the
 * `IssuanceCborHex` template and the upgrade-multisig tree). The redeemers a
 * bond transaction produces live in the library (`@contracts-library/meshjs`).
 */

import { mConStr, mConStr0, mConStr1, type Data } from "@meshsdk/core";

import {
  credentialToData,
  registryNodeToData,
  type Credential,
  type RegistryNode,
} from "@contracts-library/meshjs";

export { credentialToData, registryNodeToData };
export type { Credential, RegistryNode };

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

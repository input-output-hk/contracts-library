/**
 * Applies the CIP-113 core parameters in the documented dependency order
 * (08-INTEGRATION-GUIDES.md "Deriving Protocol and Registry Identifiers").
 *
 * This is test-only deployment tooling: the one-shot `OutputReference`
 * parameters are the funded wallet UTxOs the genesis transactions will spend.
 */

import { mConStr0, type PlutusScript } from "@meshsdk/core";

import { credentialToData, type Credential } from "@contracts-library/meshjs";

import { applyScript, scriptHashOf } from "./core";
import {
  alwaysFailCompiledCode,
  issuanceCborHexMintCompiledCode,
  issuanceLogicCompiledCode,
  programmableLogicBaseCompiledCode,
  programmableLogicGlobalCompiledCode,
  protocolParamsCompiledCode,
  registryCompiledCode,
  thirdPartyCompiledCode,
  transferCompiledCode,
  unfrackingCompiledCode,
  upgradeMultisigCompiledCode,
} from "./blueprint";

export interface OneShot {
  txHash: string;
  outputIndex: number;
}

function outputRef(ref: OneShot) {
  return mConStr0([ref.txHash, ref.outputIndex]);
}

export interface CoreConfig {
  networkId: 0 | 1;
  /** Compile-time bound on inline datums (same for transfer/third_party/unfracking/issuance_logic). */
  maxInlineDatumBytes: number;
  /** Arbitrary nonce for the always-fail lock. */
  alwaysFailNonce: string;
  /** One-shot refs spent by the genesis transactions. */
  protocolParamsRef: OneShot;
  registryRef: OneShot;
  cborHexRef: OneShot;
  /** One-shot ref spent to mint the upgrade-multisig config NFT. */
  upgradeConfigRef: OneShot;
}

export interface CoreScripts {
  alwaysFail: PlutusScript;
  protocolParams: PlutusScript;
  issuanceCborHexMint: PlutusScript;
  registry: PlutusScript;
  programmableLogicBase: PlutusScript;
  transfer: PlutusScript;
  thirdParty: PlutusScript;
  unfracking: PlutusScript;
  issuanceLogic: PlutusScript;
  programmableLogicGlobal: PlutusScript;
  upgradeMultisig: PlutusScript;

  alwaysFailHash: string;
  /** Applied `issuance_cbor_hex_mint` policy id (registry's reference NFT). */
  cborHexCs: string;
  /** Registry node NFT policy id / node address payment credential. */
  registryNodeCs: string;
  /** Protocol-params NFT policy id / params address payment credential. */
  paramsPolicy: string;
  programmableLogicBaseCred: Credential;
  transferHash: string;
  thirdPartyHash: string;
  unfrackingHash: string;
  issuanceLogicHash: string;
  programmableLogicGlobalHash: string;
  upgradeMultisigHash: string;
}

export function applyCoreScripts(cfg: CoreConfig): CoreScripts {
  const alwaysFail = applyScript(alwaysFailCompiledCode, [cfg.alwaysFailNonce]);
  const alwaysFailHash = scriptHashOf(alwaysFail);

  const protocolParams = applyScript(protocolParamsCompiledCode, [
    outputRef(cfg.protocolParamsRef),
  ]);
  const paramsPolicy = scriptHashOf(protocolParams);

  const issuanceCborHexMint = applyScript(issuanceCborHexMintCompiledCode, [
    outputRef(cfg.cborHexRef),
    alwaysFailHash,
  ]);
  const cborHexCs = scriptHashOf(issuanceCborHexMint);

  const registry = applyScript(registryCompiledCode, [outputRef(cfg.registryRef), cborHexCs]);
  const registryNodeCs = scriptHashOf(registry);

  const programmableLogicBase = applyScript(programmableLogicBaseCompiledCode, [
    paramsPolicy,
  ]);
  const plbHash = scriptHashOf(programmableLogicBase);
  const programmableLogicBaseCred: Credential = { kind: "script", hash: plbHash };

  const delegateParams = [
    credentialToData(programmableLogicBaseCred),
    registryNodeCs,
    cfg.maxInlineDatumBytes,
  ];
  const transfer = applyScript(transferCompiledCode, delegateParams);
  const thirdParty = applyScript(thirdPartyCompiledCode, delegateParams);
  const unfracking = applyScript(unfrackingCompiledCode, delegateParams);
  const transferHash = scriptHashOf(transfer);
  const thirdPartyHash = scriptHashOf(thirdParty);
  const unfrackingHash = scriptHashOf(unfracking);

  const issuanceLogic = applyScript(issuanceLogicCompiledCode, [
    credentialToData(programmableLogicBaseCred),
    registryNodeCs,
    paramsPolicy,
    cfg.maxInlineDatumBytes,
  ]);
  const issuanceLogicHash = scriptHashOf(issuanceLogic);

  const programmableLogicGlobal = applyScript(programmableLogicGlobalCompiledCode, [
    transferHash,
    thirdPartyHash,
    unfrackingHash,
  ]);

  const upgradeMultisig = applyScript(upgradeMultisigCompiledCode, [
    outputRef(cfg.upgradeConfigRef),
  ]);

  return {
    alwaysFail,
    protocolParams,
    issuanceCborHexMint,
    registry,
    programmableLogicBase,
    transfer,
    thirdParty,
    unfracking,
    issuanceLogic,
    programmableLogicGlobal,
    upgradeMultisig,
    alwaysFailHash,
    cborHexCs,
    registryNodeCs,
    paramsPolicy,
    programmableLogicBaseCred,
    transferHash,
    thirdPartyHash,
    unfrackingHash,
    issuanceLogicHash,
    programmableLogicGlobalHash: scriptHashOf(programmableLogicGlobal),
    upgradeMultisigHash: scriptHashOf(upgradeMultisig),
  };
}

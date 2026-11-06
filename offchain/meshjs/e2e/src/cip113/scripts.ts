/**
 * Applies the CIP-113 core parameters in the documented dependency order
 * (08-INTEGRATION-GUIDES.md "Deriving Protocol and Registry Identifiers").
 *
 * This is test-only deployment tooling: the one-shot `OutputReference`
 * parameters are the funded wallet UTxOs the genesis transactions will spend.
 */

import {
  applyScript,
  type CoreConfig,
  type CoreScripts,
  type Credential,
  credentialToData,
  type OneShot,
  scriptHashOf,
} from "@contracts-library/meshjs";
import { mConStr0 } from "@meshsdk/core";
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

function outputRef(ref: OneShot) {
  return mConStr0([ref.txHash, ref.outputIndex]);
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

  const registry = applyScript(registryCompiledCode, [
    outputRef(cfg.registryRef),
    cborHexCs,
  ]);
  const registryNodeCs = scriptHashOf(registry);

  const programmableLogicBase = applyScript(programmableLogicBaseCompiledCode, [
    paramsPolicy,
  ]);
  const plbHash = scriptHashOf(programmableLogicBase);
  const programmableLogicBaseCred: Credential = {
    kind: "script",
    hash: plbHash,
  };

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

  const programmableLogicGlobal = applyScript(
    programmableLogicGlobalCompiledCode,
    [transferHash, thirdPartyHash, unfrackingHash],
  );

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

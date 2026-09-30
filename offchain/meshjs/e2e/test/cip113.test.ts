/**
 * Offline validation of the CIP-113 core offchain layer (no devnet needed):
 * parameter application in dependency order, ledger-correct hashes, and the
 * IssuanceCborHex registration template.
 */

import { mConStr1, resolveScriptHash } from "@meshsdk/core";
import {
  issuanceScript,
  nativeMintPolicyScript,
  thirdPartyScript,
  transferScript,
  transformationScript,
  type MintingParams,
} from "@contracts-library/meshjs";
import { describe, expect, it } from "vitest";

import { issuanceMintCompiledCode } from "../src/cip113/blueprint";
import { applyScript, scriptHashOf } from "../src/cip113/core";
import { applyCoreScripts, type CoreConfig } from "../src/cip113/scripts";
import { issuanceTemplate } from "../src/cip113/template";

const CONFIG: CoreConfig = {
  networkId: 0,
  maxInlineDatumBytes: 1024,
  alwaysFailNonce: "ab".repeat(32),
  protocolParamsRef: { txHash: "11".repeat(32), outputIndex: 0 },
  registryRef: { txHash: "22".repeat(32), outputIndex: 1 },
  cborHexRef: { txHash: "33".repeat(32), outputIndex: 2 },
  upgradeStubHash: "ff".repeat(28),
};

const REF_NAME = "524546323232"; // "REF222"
const PRINCIPAL_NAME = "424f4e44"; // "BOND"
const SCHEDULE = [
  { deadline: 1000, value: 1040 },
  { deadline: 2000, value: 1081 },
  { deadline: 3000, value: 1124 },
  { deadline: 4000, value: 1169 },
];

describe("cip113 core offchain", () => {
  it("applies every core validator to a 28-byte hash in dependency order", () => {
    const core = applyCoreScripts(CONFIG);
    for (const h of [
      core.alwaysFailHash,
      core.cborHexCs,
      core.registryNodeCs,
      core.paramsPolicy,
      core.transferHash,
      core.thirdPartyHash,
      core.unfrackingHash,
      core.issuanceLogicHash,
      core.programmableLogicGlobalHash,
    ]) {
      expect(h).toMatch(/^[0-9a-f]{56}$/);
    }
  });

  it("derives the bond policy id from the applied issuance_mint script", () => {
    const core = applyCoreScripts(CONFIG);

    const transfer = transferScript({
      registryNodeCs: core.registryNodeCs,
      finalDeadline: 4000,
    });
    const thirdParty = thirdPartyScript({
      registryNodeCs: core.registryNodeCs,
      finalDeadline: 4000,
    });
    const transformation = transformationScript({
      referenceName: REF_NAME,
      schedule: SCHEDULE,
    });
    const mintingParams: MintingParams = {
      registryNodeCs: core.registryNodeCs,
      issuer: { kind: "key", hash: "ab".repeat(28) },
      transferLogic: scriptHashOf(transfer),
      thirdPartyLogic: scriptHashOf(thirdParty),
      transformationScript: scriptHashOf(transformation),
      principalName: PRINCIPAL_NAME,
      referenceName: REF_NAME,
      schedule: SCHEDULE,
      scale: 1000,
    };
    const issuance = issuanceScript(mintingParams);
    const nativeMint = nativeMintPolicyScript({
      cipPolicy: "00".repeat(28),
      principalName: PRINCIPAL_NAME,
      scale: 1000,
      schedule: SCHEDULE,
    });
    expect(scriptHashOf(nativeMint)).toMatch(/^[0-9a-f]{56}$/);

    // issuance_mint applied to our minting-logic credential IS the bond policy.
    const issuanceHash = scriptHashOf(issuance);
    const appliedMint = applyScript(issuanceMintCompiledCode, [
      mConStr1([issuanceHash]),
      core.paramsPolicy,
    ]);
    const bondPolicy = resolveScriptHash(appliedMint.code, appliedMint.version);
    expect(bondPolicy).toMatch(/^[0-9a-f]{56}$/);

    // The registration template splits the applied contract around the hash and
    // reconstructs it exactly (checked inside `issuanceTemplate`).
    const template = issuanceTemplate(
      issuanceMintCompiledCode,
      issuanceHash,
      core.paramsPolicy,
    );
    expect(template.prefix.length).toBeGreaterThan(0);
    expect(template.postfix.length).toBeGreaterThan(0);
    expect(template.prefix).toMatch(/d87a9f581c$/);
    expect(template.postfix).toMatch(/^ff/);
  });
});

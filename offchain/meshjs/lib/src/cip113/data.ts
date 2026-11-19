/**
 * Encoders for the CIP-113 core datums/redeemers a module transaction must
 * produce, matching `cip113-programmable-tokens/lib/types.ak` (constructor
 * order matters).
 *
 * Deploy-only encoders (protocol params, the `IssuanceCborHex` template, the
 * upgrade-multisig tree) live with the deployment tooling in `e2e/`.
 */

import { mConStr0, mConStr1, mConStr2, type Data } from "@meshsdk/core";

import { credentialToData, type Credential } from "../common";

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
  entries: { policy: string; index: number; proof?: "output" | "ref" }[],
): Data {
  return new Map(
    entries.map(
      (e) =>
        [
          e.policy,
          e.proof === "ref" ? mConStr0([e.index]) : mConStr1([e.index]),
        ] as [string, Data],
    ),
  );
}

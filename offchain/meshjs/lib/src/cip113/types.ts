/**
 * CIP-113 core deployment types shared by the library's real-core builders.
 *
 * The core framework (PLB, dispatcher, delegates, issuance, registry) lives in
 * `cardano-foundation/cip113-programmable-tokens`. The library composes with a
 * deployment of it: a `CoreDeployment` carries the applied core scripts, the
 * reference UTxOs a module transaction needs, and the raw `issuance_mint` code
 * used to derive each token policy id. Deploying the core is the caller's job
 * (the e2e suite bootstraps a devnet core; see `e2e/src/cip113/`).
 */

import type { PlutusScript, UTxO } from "@meshsdk/core";

import type { Credential } from "../common";

export type { Credential };

/** A one-shot output reference (a UTxO consumed by a genesis mint). */
export interface OneShot {
  txHash: string;
  outputIndex: number;
}

/** Compile-time parameters of the core deployment. */
export interface CoreConfig {
  networkId: 0 | 1;
  /** Bound on inline datums, the same for transfer/third_party/unfracking/issuance_logic. */
  maxInlineDatumBytes: number;
  /** Arbitrary nonce for the always-fail lock. */
  alwaysFailNonce: string;
  /** One-shot refs spent by the core genesis transactions. */
  protocolParamsRef: OneShot;
  registryRef: OneShot;
  cborHexRef: OneShot;
  upgradeConfigRef: OneShot;
}

/** The applied core scripts and the identifiers derived from them. */
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
  /** Applied `issuance_cbor_hex_mint` policy id (the registry's reference NFT). */
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

/** UTxOs every module transaction reads as reference inputs. */
export interface CoreRefs {
  /** The protocol-params UTxO (read by PLB / issuance_mint / issuance_logic). */
  protocolParams: UTxO;
  /** The `IssuanceCborHex` template UTxO (read at registration). */
  cborHex: UTxO;
  /** The registry's origin node (the covering node for the first insert). */
  originNode: UTxO;
}

/**
 * A live CIP-113 core deployment: applied scripts, reference UTxOs and the raw
 * `issuance_mint` program (to apply each token's per-policy mint script).
 */
export interface CoreDeployment {
  config: CoreConfig;
  core: CoreScripts;
  refs: CoreRefs;
  /** The compiled `issuance_mint` code (unparameterized). */
  issuanceMintCode: string;
}

/** The Plutus language version every validator in this package targets. */
export const cip113PlutusVersion = "V3" as const;

/**
 * Off-chain mirror of `onchain/lib/event_triggered/types.ak` — the tokenized
 * bond (docs/event-triggered-assets/spec.md).
 *
 * Hashes and asset names are hex strings (28-byte hashes = 56 hex chars);
 * asset names here are the hex encoding of the token name bytes.
 */

import type { Data } from "@meshsdk/core";

import type { Credential } from "../common";

export type { Credential };

/** One step of the baked schedule (§3.5): at `deadline` the value steps to
 * `value` (fixed-point `scale` units). `deadline` is POSIX milliseconds. */
export interface ScheduleStep {
  deadline: number;
  value: number;
}

export type Schedule = ScheduleStep[];

/** Compile-time parameters of the issuance (minting) logic (§4.1, §4.5). */
export interface MintingParams {
  /** The governed policy id (`cip_policy`). */
  ownPolicy: string;
  /** Policy of the core registry's node NFTs. */
  registryNodeCs: string;
  /** Registration authority (issuer). */
  issuer: Credential;
  /** Script hash of the permissive transfer logic. */
  transferLogic: string;
  /** Script hash of the graduation-only third-party logic. */
  thirdPartyLogic: string;
  /** Script hash of the transformation script (owns the reference token). */
  transformationScript: string;
  /** The principal asset name (hex). */
  principalName: string;
  /** The CIP-68 reference asset name (hex). */
  referenceName: string;
  /** The graduated asset's policy id. */
  nativePolicy: string;
  schedule: Schedule;
  scale: number;
}

export interface TransferParams {
  ownPolicy: string;
  finalDeadline: number;
}

export interface ThirdPartyParams {
  ownPolicy: string;
  finalDeadline: number;
}

export interface TransformationParams {
  ownPolicy: string;
  referenceName: string;
  schedule: Schedule;
}

export interface NativeMintParams {
  cipPolicy: string;
  principalName: string;
  scale: number;
  schedule: Schedule;
}

/** `extra` of the CIP-68 reference datum (§3.3). */
export interface BondExtra {
  schedule: Schedule;
  value: number;
}

/** Inline datum of the CIP-68 reference token (§3.3). */
export interface ReferenceDatum {
  metadata: Data;
  version: number;
  extra: BondExtra;
}

/** Inline datum of the principal token (§3.2): optional payout commitment. */
export interface PrincipalDatum {
  paymentCredential: Credential | null;
}

/** The core registry's node datum (§3.4). */
export interface RegistryNode {
  key: string;
  next: string;
  mintingLogic: Credential;
  transferLogic: Credential;
  thirdPartyLogic: Credential;
  unfrackingLogic: Credential | null;
  globalStateCs: string;
}

/** Mode redeemer of the issuance logic (§4.1, §4.5). */
export type MintingAction = "RegisterAndMint" | "Burn";

export type TransferAction = "Move";

export type ThirdPartyAction = "Graduate";

export type TransformationAction = "Update";

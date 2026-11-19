/**
 * Off-chain mirror of `onchain/lib/event_triggered/types.ak` — the tokenized
 * bond (docs/event-triggered-assets/spec.md).
 *
 * Hashes and asset names are hex strings (28-byte hashes = 56 hex chars);
 * asset names here are the hex encoding of the token name bytes. The
 * certificate's step is a one-byte name (`stepName`); coupon names are the
 * decimal lovelace amount (`couponName`).
 *
 * Dependency order (09-DEVELOPING-MODULES, "Finding your own policy id"): the
 * governed `cipPolicy` is the hash *of* the applied `issuance_mint` script, so
 * no module validator bakes it — only the coupon policy (outside that cone)
 * bakes it, and the vault NFT policy is independent.
 */

import type { PlutusScript } from "@meshsdk/core";

import type { Credential } from "../common";

export type { Credential };

/** Compile-time parameters of the minting logic (§4.1, §4.2, §4.5, §4.7). */
export interface MintingParams {
  /** Policy of the core registry's node NFTs. */
  registryNodeCs: string;
  /** Registration authority and issuer-trigger authority. */
  issuer: Credential;
  /** Script hash of the name-monotone transfer logic. */
  transferLogic: string;
  /** Script hash of the issuer-triggered third-party logic. */
  thirdPartyLogic: string;
  /** Script hash of the vault validator. */
  vault: string;
  /** The vault NFT policy every vault UTxO carries (I10). */
  vaultNftCs: string;
  /** The unit principal, in lovelace. */
  principal: number;
}

export interface TransferParams {
  registryNodeCs: string;
}

export interface ThirdPartyParams {
  registryNodeCs: string;
  issuer: Credential;
}

/** Compile-time parameters of the vault validator (§3.1, §4.2, §4.6). */
export interface VaultParams {
  principal: number;
  vaultNftCs: string;
}

/** Compile-time parameters of the vault NFT policy (§3.1, I10). */
export interface VaultNftParams {
  authority: Credential;
}

/** Compile-time parameters of one vault's coupon policy (§3.2, §4.5, §4.7). */
export interface CouponParams {
  /** The governed certificate policy (baked by the coupon policy). */
  cipPolicy: string;
  /** The unit principal, in lovelace — the graduation coupon name. */
  principal: number;
  /** Constant POSIX-ms interval between steps: step `k` opens at `start + k*interval`. */
  interval: number;
  /** Per-step coupon amounts; `length(amounts)` is the final step `N`. */
  amounts: number[];
}

/** Inline datum of a certificate (§3.3). */
export interface CertificateDatum {
  /** Timeline origin: the validity upper bound at deposit (POSIX ms). */
  start: number;
  /** The owner's committed payment credential for issuer-triggered claims. */
  commit: Credential | null;
  /** The coupon policy of the vault this unit deposited into. */
  cntPolicy: string;
}

/** Inline datum of a vault (§3.1). */
export interface VaultDatum {
  cntPolicy: string;
}

/** The core registry's node datum (§3.4) — seven fields, CBOR layout order. */
export interface RegistryNode {
  key: string;
  next: string;
  mintingLogic: Credential;
  transferLogic: Credential;
  thirdPartyLogic: Credential;
  unfrackingLogic: Credential;
  globalStateCs: string;
}

// ------------------------------------------------------------------ actions

/** Mode redeemer of the minting logic (§4.1, §4.2, §4.5, §4.7). */
export type MintingAction = "Register" | "Deposit" | "Advance" | "Retire";

export type TransferAction = "Move";

/** Redeemer of the issuer-triggered third-party logic (§4.5, §4.7). */
export type ThirdPartyAction = "Trigger";

/** One payout the redeemer names on a redemption (§4.6). */
export interface Payout {
  /** A bech32 address. */
  address: string;
  amount: bigint;
}

/** Redeemer of the vault validator (§4.2, §4.6). */
export type VaultAction =
  | { kind: "VaultDeposit" }
  | { kind: "Redeem"; payouts: Payout[] };

// ------------------------------------------------------------- bond objects

/** Deployment-supplied terms of one bond. */
export interface BondConfig {
  /** Unit principal in lovelace (I6). */
  principal: number;
  /** POSIX-ms interval between coupon steps. */
  interval: number;
  /** Per-step coupon amounts; `length(amounts)` is the final step `N`. */
  amounts: number[];
  /** Registration authority (also the default vault authority). */
  issuer: Credential;
  /** Vault NFT authority; defaults to `issuer`. */
  authority?: Credential;
  /** Hex asset name of each vault's NFT (one per vault). */
  vaultNftName: string;
}

/** The applied validators and policy ids of one bond deployment. */
export interface Bond {
  config: BondConfig;
  networkId: 0 | 1;
  transfer: PlutusScript;
  thirdParty: PlutusScript;
  issuance: PlutusScript;
  /** The bond's `issuance_mint` script (policy id is `cipPolicy`). */
  issuanceMint: PlutusScript;
  cipPolicy: string;
  vaultNft: PlutusScript;
  vaultNftCs: string;
  vault: PlutusScript;
  vaultHash: string;
  couponPolicy: PlutusScript;
  cntPolicy: string;
  /** Module stake credentials to register (publish consent) before use. */
  withdrawCredentials: PlutusScript[];
}

/**
 * Off-chain mirror of the on-chain types in `onchain/lib/smart_wallet/*.ak`.
 */

import type { Data, TxInput } from "@meshsdk/core";

import type { Credential } from "../common";

export type { Credential };

/**
 * One delegated withdraw-0 script (spender or depositor): its hash and its own
 * `Data` (mutable state for spenders, configuration or state for depositors).
 */
export interface DelegatedScript {
  scriptHash: string;
  data: Data;
}

export interface WalletDatum {
  /** Scripts that must run and approve on every `Spend` (keys fixed on spend). */
  spenders: DelegatedScript[];
  /** Scripts that must run and approve on every `Deposit` (keys fixed on deposit). */
  depositors: DelegatedScript[];
}

/** The base M-of-N config the wallet reads from a settings UTxO. */
export interface WalletConfig {
  members: string[];
  threshold: number;
}

/** The `smart_wallet` multivalidator's compile-time parameters. */
export interface WalletParams {
  seedUtxo: TxInput;
  settingsPolicy: string;
  settingsTokenName: string;
  walletTokenName: string;
  admin: Credential;
}

/**
 * Common parameters for wallet-pinned delegated withdrawal scripts: the
 * wallet's payment credential and the asset name of its identifying NFT.
 */
export interface WalletScriptParams {
  wallet: Credential;
  /** Asset name of the wallet's identifying NFT (hex). */
  walletTokenName: string;
}

/** `spending_limit` withdrawal script parameters. */
export interface SpendingLimitParams extends WalletScriptParams {
  bound: number;
}

/** `spending_window` withdrawal script parameters. */
export interface SpendingWindowParams extends WalletScriptParams {
  window: number;
}

/** `spending_window` mutable state (stored in the wallet datum). */
export interface SpendingWindowState {
  lastSpend: number;
}

/** `spending_period_limit` withdrawal script parameters. */
export interface SpendingPeriodLimitParams extends WalletScriptParams {
  /** Fixed period length in POSIX ms (e.g. 604_800_000 = one week). */
  interval: number;
  /** Lovelace cap per period. */
  maxSpend: number;
}

/** `spending_period_limit` mutable state (stored in the wallet datum). */
export interface SpendingPeriodState {
  /** End of the current period (POSIX ms, a multiple of `interval`); 0 = none. */
  period: number;
  /** Lovelace spent so far in the current period. */
  accSpend: number;
}

/**
 * An asset list: `Pairs<PolicyId, List<AssetName>>` on-chain — an association
 * list of `[policyId, assetNames]`. An empty `names` list means "any name of
 * that policy".
 */
export type AssetList = Array<[policy: string, names: string[]]>;

/** `full_recipient_allow_list` parameters (bech32 recipient addresses). */
export interface FullRecipientAllowListParams extends WalletScriptParams {
  allowed: string[];
}

/** `full_recipient_deny_list` parameters (bech32 recipient addresses). */
export interface FullRecipientDenyListParams extends WalletScriptParams {
  denied: string[];
}

/** `payment_staking_allow_list` parameters. */
export interface PaymentStakingAllowListParams extends WalletScriptParams {
  allowedPayments: Credential[];
  allowedStakings: Credential[];
}

/** `payment_staking_deny_list` parameters. */
export interface PaymentStakingDenyListParams extends WalletScriptParams {
  deniedPayments: Credential[];
  deniedStakings: Credential[];
}

/** `asset_allow_list` parameters. */
export interface AssetAllowListParams extends WalletScriptParams {
  allowed: AssetList;
}

/** `asset_deny_list` parameters. */
export interface AssetDenyListParams extends WalletScriptParams {
  denied: AssetList;
}

/** `asset_deposit_allow_list` parameters (depositor side; same shape). */
export type AssetDepositAllowListParams = AssetAllowListParams;

/** `asset_deposit_deny_list` parameters (depositor side; same shape). */
export type AssetDepositDenyListParams = AssetDenyListParams;

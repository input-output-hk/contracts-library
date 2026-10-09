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

/** `spending_limit` withdrawal script parameters (wallet = its payment credential). */
export interface SpendingLimitParams {
  wallet: Credential;
  bound: number;
}

/** `spending_window` withdrawal script parameters (wallet = its payment credential). */
export interface SpendingWindowParams {
  wallet: Credential;
  window: number;
}

/** `spending_window` mutable state (stored in the wallet datum). */
export interface SpendingWindowState {
  lastSpend: number;
}

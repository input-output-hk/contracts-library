/**
 * Off-chain mirror of on-chain types in
 * `onchain/lib/prediction-market-conditional-token/types.ak`.
 *
 * See docs/explorations/prediction-market-conditional-token.md §4.
 */

import type { Credential } from "../common";

export type { Credential };

export interface AssetClass {
  policyId: string;
  assetName: string;
}

export interface TokenInfo {
  asset: AssetClass;
  amount: bigint;
}

export type Winner = "Yes" | "No" | "Draw";

export type Option<T> = "None" | { kind: "Some"; value: T };

export interface OutcomeDatum {
  marketId: string;
  cutoff: number;
  winner: Option<Winner>;
  outcomeCredential: Credential;
  resolutionTimeout: number;
  claimDeadline: number;
  collateral: TokenInfo;
}

export interface RedemptionDatum {
  marketId: string;
  beaconPolicy: string;
}

export type RedemptionRedeemer =
  | { variant: "RedeemWinner"; outputIndex: number }
  | { variant: "BurnCompleteSet"; outputIndex: number }
  | { variant: "ClaimTimeout"; outputIndex: number }
  | { variant: "ClaimDraw"; outputIndex: number }
  | { variant: "SweepResidual"; outputIndex: number };

export type MintAction =
  | { variant: "MintSet"; marketId: string }
  | { variant: "BurnSet"; marketId: string }
  | { variant: "BurnWinner"; marketId: string };

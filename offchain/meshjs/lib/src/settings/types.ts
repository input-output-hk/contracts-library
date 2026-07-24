/**
 * Off-chain mirror of the on-chain types in `onchain/lib/settings/types.ak`.
 */

import type { Credential } from "../common";

export type { Credential };

export interface SettingsDatum {
  current: Data;
  next: Data | null;
  nextApply: number | null;
}

export interface SettingsParams {
  seedUtxo: OutputRef;
  proposeAuth: Credential;
  applyAuth: Credential;
  applyDelay: number;
}

export interface OutputRef {
  transactionId: string;
  outputIndex: number;
}

type Data = any;

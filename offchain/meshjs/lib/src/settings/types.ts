/**
 * Off-chain mirror of the on-chain types in `onchain/lib/settings/types.ak`.
 */

import type { Data, TxInput } from "@meshsdk/core";

import type { Credential } from "../common";

export type { Credential };

export interface SettingsDatum {
  current: Data;
  next: Data | null;
  nextApply: number | null;
}

export interface SettingsParams {
  seedUtxo: TxInput;
  proposeAuth: Credential;
  applyAuth: Credential;
  applyDelay: number;
  settingsTokenName: string;
}

/**
 * Off-chain mirror of the on-chain types in `onchain/lib/settings/types.ak`.
 */

import type { Credential } from "../common";
import type { TxInput } from "@meshsdk/core";

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

type Data = any;

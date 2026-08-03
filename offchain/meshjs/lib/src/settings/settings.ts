/**
 * Transaction builders for the settings contract (MeshJS).
 *
 * Action set:
 *   - `buildLaunchTx`   create the settings state (mint NFT, spend seed UTxO)
 *   - `buildProposeTx` propose a new value (update datum.next / next_apply)
 *   - `buildApplyTx`   apply a pending proposal after delay
 *   - `buildCloseTx`   burn the NFT and close the settings instance
 */

import {
  applyParamsToScript,
  resolveScriptHash,
  serializePlutusScript,
  SLOT_CONFIG_NETWORK,
  unixTimeToEnclosingSlot,
  type Asset,
  type Data,
  type MeshTxBuilder,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import type { Credential } from "../common";
import { compiledCode, plutusVersion } from "./blueprint";
import {
  applyRedeemer,
  burnRedeemer,
  closeRedeemer,
  mintRedeemer,
  paramsToData,
  proposeRedeemer,
  settingsDatumToData,
} from "./datum";
import type { SettingsDatum, SettingsParams } from "./types";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

export const SETTINGS_TOKEN_NAME = "73657474696e6773"; // hex-encoded "settings"

export function settingsScript(params: SettingsParams): PlutusScript {
  const code = applyParamsToScript(compiledCode, paramsToData(params), "Mesh");
  return { code: code, version: plutusVersion };
}

export function settingsScriptAddress(
  script: PlutusScript,
  networkId = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

// ---------------------------------------------------- Mint

export interface MintParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  seedUtxo: UTxO;
  datum: SettingsDatum;
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  applyAuth: Credential;
  network?: Network;
}

export async function buildLaunchTx(p: MintParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const scriptAddr = settingsScriptAddress(p.script, networkId);
  const policyId = resolveScriptHash(p.script.code, p.script.version);

  const settingsAsset: Asset = {
    unit: policyId + SETTINGS_TOKEN_NAME,
    quantity: "1",
  };

  applyAuthorization(p.txBuilder, p.applyAuth, p.authorizer, networkId);

  p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", policyId, SETTINGS_TOKEN_NAME)
    .mintRedeemerValue(mintRedeemer(p.outputIndex))
    .mintingScript(p.script.code)
    .txIn(
      p.seedUtxo.input.txHash,
      p.seedUtxo.input.outputIndex,
      p.seedUtxo.output.amount,
      p.seedUtxo.output.address,
    );

  return await p.txBuilder
    .txOut(scriptAddr, [
      { unit: "lovelace", quantity: DEFAULT_MIN_UTXO_LOVELACE.toString() },
      settingsAsset,
    ])
    .txOutInlineDatumValue(settingsDatumToData(p.datum))
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ---------------------------------------------------- Propose

export interface ProposeParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  settingsUtxo: UTxO;
  datum: SettingsDatum;
  newValue: Data;
  now: number;
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  proposeAuth: Credential;
  applyDelay: number;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

export async function buildProposeTx(p: ProposeParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const lowerBoundSlot = unixTimeToEnclosingSlot(p.now, slotConfig);
  const slotStartMs =
    slotConfig.zeroTime +
    (lowerBoundSlot - slotConfig.zeroSlot) * slotConfig.slotLength;
  const scriptAddr = settingsScriptAddress(p.script, networkId);

  const newDatum: SettingsDatum = {
    current: p.datum.current,
    next: p.newValue,
    nextApply: slotStartMs + p.applyDelay,
  };

  applyAuthorization(p.txBuilder, p.proposeAuth, p.authorizer, networkId);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
      p.settingsUtxo.output.amount,
      p.settingsUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(proposeRedeemer(p.outputIndex))
    .txInScript(p.script.code);

  return await p.txBuilder
    .txOut(scriptAddr, p.settingsUtxo.output.amount)
    .txOutInlineDatumValue(settingsDatumToData(newDatum))
    .invalidBefore(lowerBoundSlot)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ---------------------------------------------------- Apply

export interface ApplyParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  settingsUtxo: UTxO;
  datum: SettingsDatum;
  now: number;
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  applyAuth: Credential;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

export async function buildApplyTx(p: ApplyParams): Promise<string> {
  if (p.datum.next === null || p.datum.nextApply === null) {
    throw new Error("No pending proposal to apply");
  }

  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const lowerBoundSlot = unixTimeToEnclosingSlot(p.now, slotConfig);
  const slotStartMs =
    slotConfig.zeroTime +
    (lowerBoundSlot - slotConfig.zeroSlot) * slotConfig.slotLength;

  if (slotStartMs < p.datum.nextApply) {
    throw new Error(
      `Cannot apply before next_apply (${p.datum.nextApply}, now ${slotStartMs})`,
    );
  }

  const scriptAddr = settingsScriptAddress(p.script, networkId);

  const newDatum: SettingsDatum = {
    current: p.datum.next,
    next: null,
    nextApply: null,
  };

  applyAuthorization(p.txBuilder, p.applyAuth, p.authorizer, networkId);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
      p.settingsUtxo.output.amount,
      p.settingsUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(applyRedeemer(p.outputIndex))
    .txInScript(p.script.code);

  return await p.txBuilder
    .txOut(scriptAddr, p.settingsUtxo.output.amount)
    .txOutInlineDatumValue(settingsDatumToData(newDatum))
    .invalidBefore(lowerBoundSlot)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ---------------------------------------------------- Close

export interface CloseParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  settingsUtxo: UTxO;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  applyAuth: Credential;
  network?: Network;
}

export async function buildCloseTx(p: CloseParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const policyId = resolveScriptHash(p.script.code, p.script.version);

  applyAuthorization(p.txBuilder, p.applyAuth, p.authorizer, networkId);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
      p.settingsUtxo.output.amount,
      p.settingsUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(closeRedeemer())
    .txInScript(p.script.code)
    .mintPlutusScriptV3()
    .mint("-1", policyId, SETTINGS_TOKEN_NAME)
    .mintRedeemerValue(burnRedeemer())
    .mintingScript(p.script.code);

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

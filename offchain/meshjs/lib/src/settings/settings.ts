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
  type Asset,
  applyParamsToScript,
  type Data,
  type MeshTxBuilder,
  type Network,
  type PlutusScript,
  resolveScriptHash,
  SLOT_CONFIG_NETWORK,
  type SlotConfig,
  serializePlutusScript,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import {
  type Credential,
  enclosingSlotBound,
  finalizeTx,
  networkIdOf,
  slotBound,
} from "../common";
import { compiledCode, plutusVersion, typedCompiledCode } from "./blueprint";
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

const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

export const SETTINGS_TOKEN_NAME = "73657474696e6773"; // hex-encoded "settings"

/**
 * The propose transaction's bounded validity window, in slots past the
 * enclosing slot of `now` (spec §5.b): the validator anchors `next_apply` to
 * the window's upper bound, which must cover the inclusion slot.
 */
export const PROPOSE_WINDOW_SLOTS = 30;

export function settingsScript(params: SettingsParams): PlutusScript {
  const code = applyParamsToScript(compiledCode, paramsToData(params), "Mesh");
  return { code: code, version: plutusVersion };
}

/**
 * Parameterized script for the `settings_typed` fork, whose `validate_datum`
 * requires the setting value to be `Constr(0, [_])` (spec §3.d, §6.d R7).
 * Everything else behaves like the reference `settings` contract.
 */
export function settingsTypedScript(params: SettingsParams): PlutusScript {
  const code = applyParamsToScript(
    typedCompiledCode,
    paramsToData(params),
    "Mesh",
  );
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
  /** Minimum lovelace on the settings output (default `DEFAULT_MIN_UTXO_LOVELACE`). */
  minUtxoLovelace?: bigint;
}

export async function buildLaunchTx(p: MintParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const scriptAddr = settingsScriptAddress(p.script, networkId);
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;

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
    )
    .txOut(scriptAddr, [
      { unit: "lovelace", quantity: minLovelace.toString() },
      settingsAsset,
    ])
    .txOutInlineDatumValue(settingsDatumToData(p.datum));

  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.changeAddress,
    utxos: p.utxos,
  });
}

// ---------------------------------------------------- Propose

/** Default validity window of a propose transaction: 10 minutes after `now`. */
export const DEFAULT_PROPOSE_TTL_MS = 10 * 60 * 1000;

/** The propose transaction's validity window and the `next_apply` it bakes. */
export interface ProposalTiming {
  /** Slot passed to `invalidBefore`: the transaction is invalid before it. */
  sinceSlot: number;
  /** Slot passed to `invalidHereafter`: the transaction is invalid from it on. */
  untilSlot: number;
  /** POSIX ms the validator reads as the validity range's exclusive upper bound. */
  untilMs: number;
  /** `untilMs + applyDelay`: the earliest time the proposal can be applied. */
  nextApply: number;
}

/**
 * Timing of a proposal submitted at `now`. The validator anchors the delay on
 * the validity range's upper bound (it requires `next_apply >= upper +
 * apply_delay`), because a transaction cannot land after it. The window is
 * `ttlMs` of slots past the slot enclosing `now`; `invalidHereafter(untilSlot)`
 * makes the transaction invalid from `untilSlot` on, so the exclusive upper
 * bound the validator sees is `untilSlot`'s start time.
 */
export function proposalTiming(p: {
  now: number;
  applyDelay: number;
  slotConfig: SlotConfig;
  /** Validity window in ms after `now` (default `DEFAULT_PROPOSE_TTL_MS`). */
  ttlMs?: number;
}): ProposalTiming {
  const { slot: sinceSlot } = enclosingSlotBound(p.now, p.slotConfig);
  const windowSlots = Math.ceil(
    (p.ttlMs ?? DEFAULT_PROPOSE_TTL_MS) / p.slotConfig.slotLength,
  );
  const untilSlot = sinceSlot + windowSlots;
  const untilMs =
    p.slotConfig.zeroTime +
    (untilSlot - p.slotConfig.zeroSlot) * p.slotConfig.slotLength;
  return { sinceSlot, untilSlot, untilMs, nextApply: untilMs + p.applyDelay };
}

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
  /** Propose validity window in slots past `now` (default `PROPOSE_WINDOW_SLOTS`). */
  validityWindowSlots?: number;
  /** Validity window in ms after `now`; overrides `validityWindowSlots`. */
  ttlMs?: number;
}

export async function buildProposeTx(p: ProposeParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const timing = proposalTiming({
    now: p.now,
    applyDelay: p.applyDelay,
    slotConfig,
    ttlMs:
      p.ttlMs ??
      (p.validityWindowSlots ?? PROPOSE_WINDOW_SLOTS) * slotConfig.slotLength,
  });
  const scriptAddr = settingsScriptAddress(p.script, networkId);

  const newDatum: SettingsDatum = {
    current: p.datum.current,
    next: p.newValue,
    nextApply: timing.nextApply,
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
    .txInScript(p.script.code)
    .txOut(scriptAddr, p.settingsUtxo.output.amount)
    .txOutInlineDatumValue(settingsDatumToData(newDatum))
    .invalidBefore(timing.sinceSlot)
    .invalidHereafter(timing.untilSlot);
  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.changeAddress,
    utxos: p.utxos,
  });
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
  const { slot: lowerBoundSlot, startMs: slotStartMs } = slotBound(
    network,
    p.now,
    p.customSlotConfig,
  );

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
    .txInScript(p.script.code)
    .txOut(scriptAddr, p.settingsUtxo.output.amount)
    .txOutInlineDatumValue(settingsDatumToData(newDatum))
    .invalidBefore(lowerBoundSlot);
  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.changeAddress,
    utxos: p.utxos,
  });
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
  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.changeAddress,
    utxos: p.utxos,
  });
}

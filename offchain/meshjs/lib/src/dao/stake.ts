/**
 * Transaction builders for the DAO stake-position validator (MeshJS).
 *
 * Action set:
 *   - `buildCreateStakePositionTx` mint the stake NFT and lock the first stake
 *   - `buildDepositTx`              add more staked tokens
 *   - `buildWithdrawTx`             remove free staked tokens
 *   - `buildDelegateTx`             redirect voting power
 *   - `buildClosePositionTx`        burn the stake NFT and return all stake
 */

import {
  applyParamsToScript,
  resolveScriptHash,
  serializePlutusScript,
  SLOT_CONFIG_NETWORK,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";

import { enclosingSlotBound, nftNameFromRef, type Credential } from "../common";
import {
  closeStakePositionRedeemer,
  createPositionRedeemer,
  stakePositionDatumToData,
  stakeParamsToData,
  stakeRedeemerToData,
} from "./datum";
import type { StakeParams, StakePositionDatum, StakeRedeemer } from "./types";
import { stakeCompiledCode as stakeCode, plutusVersion } from "./blueprint";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

/** The enclosing slot + start time for `now` on the given network/devnet. */
function slotBound(
  network: Network,
  now: number,
  customSlotConfig?: SlotConfig,
) {
  return enclosingSlotBound(
    now,
    customSlotConfig ?? SLOT_CONFIG_NETWORK[network],
  );
}

const DEFAULT_MIN_UTXO_LOVELACE = 2_000_000n;

/** The Plutus V3 script in the form MeshJS expects (parameterized). */
export function stakeScript(params: StakeParams): PlutusScript {
  const code = applyParamsToScript(
    stakeCode,
    stakeParamsToData(params),
    "Mesh",
  );
  return { code, version: plutusVersion };
}

export function stakeScriptAddress(
  script: PlutusScript,
  networkId = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

function assetUnit(policyId: string, assetName: string): string {
  return policyId + assetName;
}

/** The asset name held by `utxo` under `policyId` (excluding lovelace), or "". */
function nftNameOf(utxo: UTxO, policyId: string): string {
  const unit = utxo.output.amount
    .map((a) => a.unit)
    .find((u) => u !== "lovelace" && u.startsWith(policyId));
  return unit ? unit.slice(policyId.length) : "";
}

/** Add (or subtract, for negative quantities) an asset to a value list. */
function addAsset(value: Asset[], asset: Asset): Asset[] {
  const existing = value.find((a) => a.unit === asset.unit);
  if (existing) {
    existing.quantity = (
      BigInt(existing.quantity) + BigInt(asset.quantity)
    ).toString();
  } else {
    value.push({ ...asset });
  }
  return value;
}

function minusAsset(value: Asset[], unit: string, quantity: bigint): Asset[] {
  const existing = value.find((a) => a.unit === unit);
  if (existing) {
    existing.quantity = (BigInt(existing.quantity) - quantity).toString();
  }
  return value.filter((a) => BigInt(a.quantity) !== 0n);
}

/** Value of a fresh stake position: ada + stake NFT + held stake. */
function createPositionValue(
  script: PlutusScript,
  stakeNftName: string,
  held: Asset[],
): Asset[] {
  const value: Asset[] = [
    { unit: "lovelace", quantity: DEFAULT_MIN_UTXO_LOVELACE.toString() },
    {
      unit: assetUnit(
        resolveScriptHash(script.code, script.version),
        stakeNftName,
      ),
      quantity: "1",
    },
  ];
  for (const a of held) addAsset(value, a);
  return value;
}

// ---------------------------------------------------- CreatePosition

export interface CreateStakePositionParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  /** The owner's UTxO funding the locked stake + fees. */
  seedUtxo: UTxO;
  owner: { keyHash: string };
  datum: StakePositionDatum;
  /** The stake-token asset(s) to lock. */
  stakedTokens: Asset[];
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/** Mint the stake NFT and lock the first stake at the stake script address. */
export async function buildCreateStakePositionTx(
  p: CreateStakePositionParams,
): Promise<string> {
  const network = p.network ?? "preprod";
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const scriptAddr = stakeScriptAddress(p.script, networkIdOf(network));
  const stakeNftName = nftNameFromRef(p.seedUtxo.input);

  p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", policyId, stakeNftName)
    .mintRedeemerValue(createPositionRedeemer(p.seedUtxo.input, 0))
    .mintingScript(p.script.code)
    .txIn(
      p.seedUtxo.input.txHash,
      p.seedUtxo.input.outputIndex,
      p.seedUtxo.output.amount,
      p.seedUtxo.output.address,
    );

  p.txBuilder.requiredSignerHash(p.owner.keyHash);

  return await p.txBuilder
    .txOut(
      scriptAddr,
      createPositionValue(p.script, stakeNftName, p.stakedTokens),
    )
    .txOutInlineDatumValue(stakePositionDatumToData(p.datum))
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

// ---------------------------------------------------- generic spend

export interface StakeSpendParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  /** The stake position UTxO being acted on. */
  stakeUtxo: UTxO;
  settingsUtxo: UTxO;
  /** The position owner (added as a required signer when a key credential). */
  owner: Credential;
  /** Wall-clock used to set the validity lower bound (POSIX ms). */
  now: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

/**
 * Build a spend of a stake position with the given redeemer, continuing the
 * position with `continuationValue` and `continuationDatum` (or none for close).
 */
async function buildStakeSpend(
  p: StakeSpendParams,
  redeemer: StakeRedeemer,
  continuation: {
    value: Asset[];
    datum: StakePositionDatum;
  } | null,
): Promise<string> {
  const network = p.network ?? "preprod";
  const scriptAddr = stakeScriptAddress(p.script, networkIdOf(network));
  const bound = slotBound(network, p.now, p.customSlotConfig);

  if (p.owner.kind === "key") {
    p.txBuilder.requiredSignerHash(p.owner.hash);
  }

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(stakeRedeemerToData(redeemer))
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    );

  if (continuation) {
    p.txBuilder
      .txOut(scriptAddr, continuation.value)
      .txOutInlineDatumValue(stakePositionDatumToData(continuation.datum));
  }

  return await p.txBuilder
    .invalidBefore(bound.slot)
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

// ---------------------------------------------------- Deposit

export interface DepositParams extends StakeSpendParams {
  /** The position's datum (continuing). */
  datum: StakePositionDatum;
  /** Extra stake-token asset(s) added by the owner. */
  addedTokens: Asset[];
}

export async function buildDepositTx(p: DepositParams): Promise<string> {
  const value = [...p.stakeUtxo.output.amount];
  for (const a of p.addedTokens) addAsset(value, a);
  return buildStakeSpend(p, { kind: "Deposit" }, { value, datum: p.datum });
}

// ---------------------------------------------------- Withdraw

export interface WithdrawParams extends StakeSpendParams {
  /** The position's datum (continuing). */
  datum: StakePositionDatum;
  /** Quantity of the stake token to withdraw. */
  amount: bigint;
  /** Unit ("policyId + name") of the DAO stake token. */
  stakeTokenUnit: string;
}

export async function buildWithdrawTx(p: WithdrawParams): Promise<string> {
  const value = minusAsset(
    [...p.stakeUtxo.output.amount],
    p.stakeTokenUnit,
    p.amount,
  );
  return buildStakeSpend(
    p,
    { kind: "Withdraw", amount: p.amount },
    { value, datum: p.datum },
  );
}

// ---------------------------------------------------- Delegate

export interface DelegateParams extends StakeSpendParams {
  /** The position's datum (continuing). */
  datum: StakePositionDatum;
  delegatee: { keyHash: string } | null;
}

export async function buildDelegateTx(p: DelegateParams): Promise<string> {
  const datum: StakePositionDatum = {
    ...p.datum,
    delegatee: p.delegatee ? { kind: "key", hash: p.delegatee.keyHash } : null,
  };
  return buildStakeSpend(
    p,
    { kind: "DelegateTo", delegatee: datum.delegatee },
    { value: [...p.stakeUtxo.output.amount], datum },
  );
}

// ---------------------------------------------------- ClosePosition

export interface ClosePositionParams extends StakeSpendParams {}

export async function buildClosePositionTx(
  p: ClosePositionParams,
): Promise<string> {
  const network = p.network ?? "preprod";
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const stakeNftName = nftNameOf(p.stakeUtxo, policyId);
  const bound = slotBound(network, p.now, p.customSlotConfig);

  if (p.owner.kind === "key") {
    p.txBuilder.requiredSignerHash(p.owner.hash);
  }

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(stakeRedeemerToData({ kind: "ClosePosition" }))
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    )
    .mintPlutusScriptV3()
    .mint("-1", policyId, stakeNftName)
    .mintRedeemerValue(closeStakePositionRedeemer())
    .mintingScript(p.script.code);

  return await p.txBuilder
    .invalidBefore(bound.slot)
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

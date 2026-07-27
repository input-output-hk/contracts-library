/**
 * Transaction builders for the event-triggered assets contract (MeshJS).
 *
 * CIP-113 substandard scaffold (docs/explorations/event-triggered-assets.md):
 *   - `buildIssueTx`      mint the programmable token into programmable custody
 *   - `buildApplyEventTx` keeper-submitted, event-conditioned state change (P2)
 *   - `buildGraduateTx`   burn the programmable token and mint the graduated
 *                         native token (P3)
 *   - `buildRetireTx`     burn-only retirement (P3)
 *
 * The on-chain predicates are permissive stubs pending triage (§7, TODO(#28)).
 * The builders add the off-chain guards the on-chain does not yet enforce:
 * the repo authorization pattern (key credential → required signer, script
 * credential → withdraw-0) for the datum's `rule`/`graduationAuth`
 * authorities, plus burn-coverage and policy-identity checks on the P3 paths.
 *
 * These return an unsigned transaction (hex) from a configured
 * `MeshTxBuilder`. Signing/submission is the caller's wallet's responsibility.
 */

import {
  applyCborEncoding,
  Network,
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
  applyEventRedeemer,
  graduateRedeemer,
  instrumentDatumToData,
  retireRedeemer,
} from "./datum";
import type { EventAssetDatum } from "./types";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

/** The Plutus V3 script in the form MeshJS expects (double-CBOR-encoded). */
export function eventTriggeredScript(): PlutusScript {
  return { code: applyCborEncoding(compiledCode), version: plutusVersion };
}

/** Bech32 address of the event-triggered script (0 = testnet). */
export function eventTriggeredScriptAddress(networkId = 0): string {
  return serializePlutusScript(eventTriggeredScript(), undefined, networkId)
    .address;
}

/** The event-triggered policy id (the script's own hash). */
export function eventTriggeredPolicyId(): string {
  return resolveScriptHash(eventTriggeredScript().code, plutusVersion);
}

function splitUnit(unit: string): { policyId: string; assetName: string } {
  return { policyId: unit.slice(0, 56), assetName: unit.slice(56) };
}

function quantityOf(utxo: UTxO, unit: string): bigint {
  const a = utxo.output.amount.find((x) => x.unit === unit);
  return a ? BigInt(a.quantity) : 0n;
}

/**
 * The wallet UTxOs holding `unit`, verified to cover the burn `quantity`.
 * The burn must be balanced by inputs actually containing the asset, so the
 * holders are added to the transaction explicitly.
 */
function burnInputsOf(utxos: UTxO[], unit: string, quantity: bigint): UTxO[] {
  const holders = utxos.filter((u) => quantityOf(u, unit) > 0n);
  const total = holders.reduce((sum, u) => sum + quantityOf(u, unit), 0n);
  if (total < quantity) {
    throw new Error(
      `Inputs hold ${total} of ${unit}; need ${quantity} to burn`,
    );
  }
  return holders;
}

// ---------------------------------------------------- Issue

export interface IssueParams {
  txBuilder: MeshTxBuilder;
  /** Initial instrument state, written into the custodied UTxO's datum. */
  datum: EventAssetDatum;
  /** Asset name (hex) of the programmable token to mint. */
  assetName: string;
  /** Quantity to mint. Defaults to 1. */
  quantity?: bigint;
  /** Wallet UTxOs to fund the custodied output + fees. */
  utxos: UTxO[];
  /** Wallet change address. */
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  network?: Network;
  minUtxoLovelace?: bigint;
}

/**
 * Build an Issue transaction: mint the programmable token under the
 * event-triggered policy and place it at the script address with an inline
 * `Some(EventAssetDatum)`.
 *
 * SCAFFOLD GAP (TODO(#28)): the on-chain mint endpoint has no `Issue`
 * redeemer yet, so this mints under the permissive `Graduate` redeemer as a
 * placeholder until triage adds a dedicated constructor. The datum's `rule`
 * authority must sign (key → required signer, script → withdraw-0).
 */
export async function buildIssueTx(p: IssueParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const script = eventTriggeredScript();
  const scriptAddr = eventTriggeredScriptAddress(networkId);
  const policyId = resolveScriptHash(script.code, script.version);
  const quantity = p.quantity ?? 1n;
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;

  const custodiedAssets: Asset[] = [
    { unit: "lovelace", quantity: minLovelace.toString() },
    { unit: policyId + p.assetName, quantity: quantity.toString() },
  ];

  applyAuthorization(p.txBuilder, p.datum.rule, p.authorizer, networkId);

  return await p.txBuilder
    .mintPlutusScriptV3()
    .mint(quantity.toString(), policyId, p.assetName)
    .mintRedeemerValue(graduateRedeemer())
    .mintingScript(script.code)
    .txOut(scriptAddr, custodiedAssets)
    .txOutInlineDatumValue(instrumentDatumToData(p.datum))
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

// ---------------------------------------------------- ApplyEvent

export interface ApplyEventParams {
  txBuilder: MeshTxBuilder;
  /** The instrument UTxO being acted on. */
  instrumentUtxo: UTxO;
  /** The instrument's current state (its `rule` authority authorizes). */
  datum: EventAssetDatum;
  /** The post-event state to write into the continuing output. */
  nextDatum: EventAssetDatum;
  /** POSIX ms used as the validity-range lower bound; the on-chain "now". */
  now: number;
  /** Wallet UTxOs to cover fees. */
  utxos: UTxO[];
  /** Wallet change address. */
  changeAddress: string;
  collateralUtxo: UTxO;
  authorizer?: ScriptAuthorizer;
  network?: Network;
  /**
   * Slot configuration for the time→slot conversion of the validity range.
   * Only needed on a custom network (e.g. a local Yaci devnet).
   */
  customSlotConfig?: SlotConfig;
}

/**
 * Build an ApplyEvent transaction (P2): spend the instrument UTxO and write
 * the post-event state into a continuing output at the script address.
 *
 * The permissive on-chain `validate_event` stub enforces nothing yet; the
 * builder already requires the datum's `rule` authority to authorize.
 */
export async function buildApplyEventTx(p: ApplyEventParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const lowerBoundSlot = unixTimeToEnclosingSlot(p.now, slotConfig);
  const script = eventTriggeredScript();
  const { input, output } = p.instrumentUtxo;

  applyAuthorization(p.txBuilder, p.datum.rule, p.authorizer, networkId);

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(applyEventRedeemer())
    .txInScript(script.code)
    .txOut(output.address, output.amount)
    .txOutInlineDatumValue(instrumentDatumToData(p.nextDatum))
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

// ---------------------------------------------------- Graduate

export interface GraduateParams {
  txBuilder: MeshTxBuilder;
  /** Unit (policyId + assetName, hex) of the programmable token to burn. */
  programmaticUnit: string;
  /** Quantity of the programmable token to burn. */
  programmaticQuantity: bigint;
  /** Unit of the graduated token to mint (Q-GRAD-1 identity swap). */
  graduatedUnit: string;
  /** Quantity of the graduated token to mint. */
  graduatedQuantity: bigint;
  /** Minting policy of the graduated token. Must be a Plutus script with a
   * redeemer: an atomic burn+remint swap runs two mint policies, and a
   * redeemer-less native policy desyncs the ledger's mint-redeemer indices
   * (they follow the policyId-sorted mint order). A Plutus graduated policy
   * can also consent to the swap, e.g. by requiring the burn of the
   * programmable token — the identity-preserving pattern for Q-GRAD-1. */
  graduatedScript: PlutusScript;
  /** Redeemer for the graduated policy's mint endpoint in this transaction. */
  graduatedRedeemer: Data;
  /** Wallet UTxOs; must include the UTxOs holding the tokens to burn. */
  utxos: UTxO[];
  /** Wallet change address (receives the graduated tokens). */
  changeAddress: string;
  collateralUtxo: UTxO;
  /** The instrument's `graduationAuth` authority. */
  graduationAuth: Credential;
  authorizer?: ScriptAuthorizer;
  network?: Network;
}

/**
 * Build a Graduate transaction (P3): burn the programmable token under the
 * event-triggered policy (`Graduate` redeemer) and mint the graduated token
 * under the supplied graduated policy, in one atomic swap.
 *
 * The permissive on-chain `validate_graduate` stub enforces nothing yet; the
 * builder already requires the `graduationAuth` authority to authorize and
 * checks the burn is covered and the two policies are distinct (Q-GRAD-1).
 */
export async function buildGraduateTx(p: GraduateParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const script = eventTriggeredScript();
  const policyId = resolveScriptHash(script.code, script.version);
  const programmatic = splitUnit(p.programmaticUnit);
  const graduated = splitUnit(p.graduatedUnit);

  if (programmatic.policyId !== policyId) {
    throw new Error(
      `programmaticUnit ${p.programmaticUnit} is not under the event-triggered policy ${policyId}`,
    );
  }
  if (graduated.policyId === policyId) {
    throw new Error(
      "graduatedUnit must live under a policy distinct from the event-triggered policy (Q-GRAD-1)",
    );
  }
  if (
    resolveScriptHash(p.graduatedScript.code, p.graduatedScript.version) !==
    graduated.policyId
  ) {
    throw new Error(
      "graduatedScript does not hash to graduatedUnit's policy id",
    );
  }

  const burnInputs = burnInputsOf(
    p.utxos,
    p.programmaticUnit,
    p.programmaticQuantity,
  );

  applyAuthorization(p.txBuilder, p.graduationAuth, p.authorizer, networkId);

  const txBuilder = p.txBuilder
    .mintPlutusScriptV3()
    .mint(
      "-" + p.programmaticQuantity.toString(),
      policyId,
      programmatic.assetName,
    )
    .mintRedeemerValue(graduateRedeemer())
    .mintingScript(script.code)
    .mintPlutusScriptV3()
    .mint(
      p.graduatedQuantity.toString(),
      graduated.policyId,
      graduated.assetName,
    )
    .mintRedeemerValue(p.graduatedRedeemer)
    .mintingScript(p.graduatedScript.code);

  for (const holder of burnInputs) {
    txBuilder.txIn(
      holder.input.txHash,
      holder.input.outputIndex,
      holder.output.amount,
      holder.output.address,
    );
  }

  return await txBuilder
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

// ---------------------------------------------------- Retire

export interface RetireParams {
  txBuilder: MeshTxBuilder;
  /** Unit (policyId + assetName, hex) of the programmable token to burn. */
  programmaticUnit: string;
  /** Quantity of the programmable token to burn. */
  programmaticQuantity: bigint;
  /** Wallet UTxOs; must include the UTxOs holding the tokens to burn. */
  utxos: UTxO[];
  /** Wallet change address. */
  changeAddress: string;
  collateralUtxo: UTxO;
  /** The instrument's `graduationAuth` authority. */
  graduationAuth: Credential;
  authorizer?: ScriptAuthorizer;
  network?: Network;
}

/**
 * Build a Retire transaction (P3): burn-only retirement of the programmable
 * token (`Retire` redeemer), for instruments with no graduated successor.
 *
 * The permissive on-chain `validate_retire` stub enforces nothing yet; the
 * builder already requires the `graduationAuth` authority to authorize and
 * checks the burn is covered.
 */
export async function buildRetireTx(p: RetireParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const script = eventTriggeredScript();
  const policyId = resolveScriptHash(script.code, script.version);
  const programmatic = splitUnit(p.programmaticUnit);

  if (programmatic.policyId !== policyId) {
    throw new Error(
      `programmaticUnit ${p.programmaticUnit} is not under the event-triggered policy ${policyId}`,
    );
  }

  const burnInputs = burnInputsOf(
    p.utxos,
    p.programmaticUnit,
    p.programmaticQuantity,
  );

  applyAuthorization(p.txBuilder, p.graduationAuth, p.authorizer, networkId);

  const txBuilder = p.txBuilder
    .mintPlutusScriptV3()
    .mint(
      "-" + p.programmaticQuantity.toString(),
      policyId,
      programmatic.assetName,
    )
    .mintRedeemerValue(retireRedeemer())
    .mintingScript(script.code);

  for (const holder of burnInputs) {
    txBuilder.txIn(
      holder.input.txHash,
      holder.input.outputIndex,
      holder.output.amount,
      holder.output.address,
    );
  }

  return await txBuilder
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

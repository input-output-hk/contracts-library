/**
 * Transaction builders for the prediction-market conditional-token settlement
 * contract.
 *
 * Implements the action set in
 * docs/explorations/prediction-market-conditional-token.md §4.
 *
 * Uses two multi-validator scripts (each handles spend + mint):
 *   Outcome:    create markets, resolve outcomes, mint beacon tokens
 *   Redemption: hold collateral, redeem positions, mint/burn outcome tokens
 *
 * **Status:** Validators are currently stubs — spend paths return True, mint
 * paths fail. Builders for spend paths work end-to-end; mint-related builders
 * are included for full API coverage but will fail against current stubs.
 */

import {
  applyCborEncoding,
  serializePlutusScript,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import { outcomeCode, plutusVersion, redemptionCode } from "./blueprint";
import {
  outcomeDatumToData,
  redemptionDatumToData,
  redemptionRedeemerToData,
  resolveRedeemer,
} from "./datum";
import type { OutcomeDatum, RedemptionDatum, TokenInfo, Winner } from "./types";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

export function outcomeScript(): PlutusScript {
  return { code: applyCborEncoding(outcomeCode), version: plutusVersion };
}

export function redemptionScript(): PlutusScript {
  return { code: applyCborEncoding(redemptionCode), version: plutusVersion };
}

export function outcomeScriptAddress(networkId = 0): string {
  return serializePlutusScript(outcomeScript(), undefined, networkId).address;
}

export function redemptionScriptAddress(networkId = 0): string {
  return serializePlutusScript(redemptionScript(), undefined, networkId)
    .address;
}

function assetUnit(policyId: string, assetName: string): string {
  return policyId === "" ? "lovelace" : policyId + assetName;
}

function tokenUnit(token: TokenInfo): string {
  return assetUnit(token.asset.policyId, token.asset.assetName);
}

function beaconUnit(beaconPolicy: string, marketId: string): string {
  return beaconPolicy + marketId;
}

function adaBundle(quantity: bigint, suffix: Asset[]): Asset[] {
  return quantity > 0n
    ? [{ unit: "lovelace", quantity: String(quantity) }, ...suffix]
    : suffix;
}

function ensureMinAda(assets: Asset[], minLovelace: bigint): Asset[] {
  const hasAda = assets.some((a) => a.unit === "lovelace");
  if (hasAda) return assets;
  return adaBundle(minLovelace, assets);
}

// ------------------------------------------------------------------ Setup

export interface SetupParams {
  txBuilder: MeshTxBuilder;
  outcomeDatum: OutcomeDatum;
  redemptionDatum: RedemptionDatum;
  collateralAmount: bigint;
  beaconPolicy: string;
  outcomeTokenPolicy: string;
  marketId: string;
  utxos: UTxO[];
  changeAddress: string;
  networkId?: number;
  minUtxoLovelace?: bigint;
}

/**
 * Build a market setup transaction.
 *
 * Creates an outcome UTxO (with a beacon token and the outcome datum) and a
 * redemption UTxO (with collateral and the redemption datum). The beacon must
 * be pre-minted externally (the mint purpose fails against current stubs).
 */
export async function buildSetupTx(p: SetupParams): Promise<string> {
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;
  const outcomeAddr = outcomeScriptAddress(p.networkId ?? 0);
  const redemptionAddr = redemptionScriptAddress(p.networkId ?? 0);

  const beaconHex = beaconUnit(p.beaconPolicy, p.marketId);
  const collateralHex = tokenUnit(p.outcomeDatum.collateral);

  const outcomeAssets: Asset[] = adaBundle(minLovelace, [
    { unit: beaconHex, quantity: "1" },
  ]);

  const redemptionAssets: Asset[] = ensureMinAda(
    [{ unit: collateralHex, quantity: String(p.collateralAmount) }],
    minLovelace,
  );

  return await p.txBuilder
    .txOut(outcomeAddr, outcomeAssets)
    .txOutInlineDatumValue(outcomeDatumToData(p.outcomeDatum))
    .txOut(redemptionAddr, redemptionAssets)
    .txOutInlineDatumValue(redemptionDatumToData(p.redemptionDatum))
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ------------------------------------------------------------------- Resolve

export interface ResolveParams {
  txBuilder: MeshTxBuilder;
  outcomeUtxo: UTxO;
  datum: OutcomeDatum;
  winner: Winner;
  changeAddress: string;
  collateralUtxo: UTxO;
  utxos: UTxO[];
  authorizer?: ScriptAuthorizer;
  network?: Network;
}

/**
 * Build a Resolve transaction. The resolution authority (identified by
 * `datum.outcomeCredential`) declares the winner.
 *
 * Spends the outcome UTxO, produces a continuation with `winner` set,
 * and preserves the beacon token.
 */
export async function buildResolveTx(p: ResolveParams): Promise<string> {
  const network = p.network ?? "preprod";
  const script = outcomeScript();
  const { input, output } = p.outcomeUtxo;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(resolveRedeemer(p.winner))
    .txInScript(script.code);

  const newDatum: OutcomeDatum = {
    ...p.datum,
    winner: { kind: "Some", value: p.winner },
  };
  p.txBuilder
    .txOut(output.address, output.amount)
    .txOutInlineDatumValue(outcomeDatumToData(newDatum));

  applyAuthorization(
    p.txBuilder,
    p.datum.outcomeCredential,
    p.authorizer,
    networkIdOf(network),
  );

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

// ------------------------------------------------------------- RedeemWinner

export interface RedeemWinnerParams {
  txBuilder: MeshTxBuilder;
  redemptionUtxo: UTxO;
  datum: RedemptionDatum;
  outcomeUtxo: UTxO;
  outcomeDatum: OutcomeDatum;
  winner: Winner;
  winTokens: bigint;
  tokenPolicy: string;
  outputIndex: number;
  beneficiaryAddress: string;
  collateralUtxo: UTxO;
  utxos: UTxO[];
  network?: Network;
}

/**
 * Build a RedeemWinner transaction.
 *
 * Spends the redemption UTxO, references the outcome UTxO to verify the winner,
 * burns winning tokens, and pays collateral to the beneficiary.
 */
export async function buildRedeemWinnerTx(
  p: RedeemWinnerParams,
): Promise<string> {
  const script = redemptionScript();
  const { input, output } = p.redemptionUtxo;
  const collateralUnit = tokenUnit(p.outcomeDatum.collateral);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      redemptionRedeemerToData({
        variant: "RedeemWinner",
        outputIndex: p.outputIndex,
      }),
    )
    .txInScript(script.code);

  p.txBuilder.readOnlyTxInReference(
    p.outcomeUtxo.input.txHash,
    p.outcomeUtxo.input.outputIndex,
  );

  p.txBuilder.txOut(p.beneficiaryAddress, [
    { unit: collateralUnit, quantity: String(p.winTokens) },
  ]);

  const continuationAmount = output.amount.map((a) => {
    if (a.unit === collateralUnit) {
      const remaining = BigInt(a.quantity) - p.winTokens;
      return {
        unit: a.unit,
        quantity: String(remaining > 0n ? remaining : 0n),
      };
    }
    return a;
  });

  const hasCollateral = continuationAmount.some(
    (a) => a.unit === collateralUnit && BigInt(a.quantity) > 0n,
  );
  if (hasCollateral) {
    p.txBuilder
      .txOut(output.address, continuationAmount)
      .txOutInlineDatumValue(redemptionDatumToData(p.datum));
  }

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.beneficiaryAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ----------------------------------------------------------- BurnCompleteSet

export interface BurnCompleteSetParams {
  txBuilder: MeshTxBuilder;
  redemptionUtxo: UTxO;
  datum: RedemptionDatum;
  outcomeUtxo: UTxO;
  outcomeDatum: OutcomeDatum;
  outputIndex: number;
  completeSets: bigint;
  beneficiaryAddress: string;
  collateralUtxo: UTxO;
  utxos: UTxO[];
  network?: Network;
}

/**
 * Build a BurnCompleteSet transaction (pre-resolution exit).
 *
 * Burns equal YES + NO tokens and returns collateral from the redemption UTxO.
 * Only valid when `winner == None` in the outcome datum.
 */
export async function buildBurnCompleteSetTx(
  p: BurnCompleteSetParams,
): Promise<string> {
  const script = redemptionScript();
  const { input, output } = p.redemptionUtxo;
  const collateralUnit = tokenUnit(p.outcomeDatum.collateral);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      redemptionRedeemerToData({
        variant: "BurnCompleteSet",
        outputIndex: p.outputIndex,
      }),
    )
    .txInScript(script.code);

  p.txBuilder.readOnlyTxInReference(
    p.outcomeUtxo.input.txHash,
    p.outcomeUtxo.input.outputIndex,
  );

  p.txBuilder.txOut(p.beneficiaryAddress, [
    { unit: collateralUnit, quantity: String(p.completeSets) },
  ]);

  const continuationAmount = output.amount.map((a) => {
    if (a.unit === collateralUnit) {
      const remaining = BigInt(a.quantity) - p.completeSets;
      return {
        unit: a.unit,
        quantity: String(remaining > 0n ? remaining : 0n),
      };
    }
    return a;
  });

  const hasCollateral = continuationAmount.some(
    (a) => a.unit === collateralUnit && BigInt(a.quantity) > 0n,
  );
  if (hasCollateral) {
    p.txBuilder
      .txOut(output.address, continuationAmount)
      .txOutInlineDatumValue(redemptionDatumToData(p.datum));
  }

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.beneficiaryAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// -------------------------------------------------------------- ClaimTimeout

export interface ClaimTimeoutParams {
  txBuilder: MeshTxBuilder;
  redemptionUtxo: UTxO;
  datum: RedemptionDatum;
  outcomeUtxo: UTxO;
  outcomeDatum: OutcomeDatum;
  outputIndex: number;
  /** Total tokens being burned (YES + NO). Each burns for 0.5 collateral. */
  tokenCount: bigint;
  beneficiaryAddress: string;
  collateralUtxo: UTxO;
  utxos: UTxO[];
  network?: Network;
}

/**
 * Build a ClaimTimeout transaction.
 *
 * After `resolution_timeout` and before `claim_deadline`, any token holder can
 * claim 0.5 collateral per token (no complete-set requirement). Produces a
 * continuation redemption UTxO with the residual collateral.
 */
export async function buildClaimTimeoutTx(
  p: ClaimTimeoutParams,
): Promise<string> {
  const script = redemptionScript();
  const { input, output } = p.redemptionUtxo;
  const collateralUnit = tokenUnit(p.outcomeDatum.collateral);

  const claimAmount = p.tokenCount / 2n;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      redemptionRedeemerToData({
        variant: "ClaimTimeout",
        outputIndex: p.outputIndex,
      }),
    )
    .txInScript(script.code);

  p.txBuilder.readOnlyTxInReference(
    p.outcomeUtxo.input.txHash,
    p.outcomeUtxo.input.outputIndex,
  );

  if (claimAmount > 0n) {
    p.txBuilder.txOut(p.beneficiaryAddress, [
      { unit: collateralUnit, quantity: String(claimAmount) },
    ]);
  }

  const continuationAmount = output.amount.map((a) => {
    if (a.unit === collateralUnit) {
      const remaining = BigInt(a.quantity) - claimAmount;
      return {
        unit: a.unit,
        quantity: String(remaining > 0n ? remaining : 0n),
      };
    }
    return a;
  });

  const hasCollateral = continuationAmount.some(
    (a) => a.unit === collateralUnit && BigInt(a.quantity) > 0n,
  );
  if (hasCollateral) {
    p.txBuilder
      .txOut(output.address, continuationAmount)
      .txOutInlineDatumValue(redemptionDatumToData(p.datum));
  }

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.beneficiaryAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ---------------------------------------------------------------- ClaimDraw

export interface ClaimDrawParams {
  txBuilder: MeshTxBuilder;
  redemptionUtxo: UTxO;
  datum: RedemptionDatum;
  outcomeUtxo: UTxO;
  outcomeDatum: OutcomeDatum;
  outputIndex: number;
  tokenCount: bigint;
  beneficiaryAddress: string;
  collateralUtxo: UTxO;
  utxos: UTxO[];
  network?: Network;
}

/**
 * Build a ClaimDraw transaction.
 *
 * After the outcome is resolved to Draw, any token holder can claim 0.5
 * collateral per token (no complete-set requirement). Produces a continuation
 * redemption UTxO with the residual collateral.
 */
export async function buildClaimDrawTx(p: ClaimDrawParams): Promise<string> {
  const script = redemptionScript();
  const { input, output } = p.redemptionUtxo;
  const collateralUnit = tokenUnit(p.outcomeDatum.collateral);

  const claimAmount = p.tokenCount / 2n;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      redemptionRedeemerToData({
        variant: "ClaimDraw",
        outputIndex: p.outputIndex,
      }),
    )
    .txInScript(script.code);

  p.txBuilder.readOnlyTxInReference(
    p.outcomeUtxo.input.txHash,
    p.outcomeUtxo.input.outputIndex,
  );

  if (claimAmount > 0n) {
    p.txBuilder.txOut(p.beneficiaryAddress, [
      { unit: collateralUnit, quantity: String(claimAmount) },
    ]);
  }

  const continuationAmount = output.amount.map((a) => {
    if (a.unit === collateralUnit) {
      const remaining = BigInt(a.quantity) - claimAmount;
      return {
        unit: a.unit,
        quantity: String(remaining > 0n ? remaining : 0n),
      };
    }
    return a;
  });

  const hasCollateral = continuationAmount.some(
    (a) => a.unit === collateralUnit && BigInt(a.quantity) > 0n,
  );
  if (hasCollateral) {
    p.txBuilder
      .txOut(output.address, continuationAmount)
      .txOutInlineDatumValue(redemptionDatumToData(p.datum));
  }

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.beneficiaryAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

// ------------------------------------------------------------- SweepResidual

export interface SweepResidualParams {
  txBuilder: MeshTxBuilder;
  redemptionUtxo: UTxO;
  datum: RedemptionDatum;
  outcomeUtxo: UTxO;
  outcomeDatum: OutcomeDatum;
  outputIndex: number;
  marketAddress: string;
  collateralUtxo: UTxO;
  /** Wallet that pays fees. */
  utxos: UTxO[];
  /**
   * Where fee-collector change goes. Distinct from `marketAddress` which
   * collects the sweep amount.
   */
  changeAddress: string;
  network?: Network;
}

/**
 * Build a SweepResidual transaction.
 *
 * After `claim_deadline`, sends the entire remaining collateral of the
 * redemption UTxO to `marketAddress` and destroys the redemption UTxO.
 */
export async function buildSweepResidualTx(
  p: SweepResidualParams,
): Promise<string> {
  const script = redemptionScript();
  const { input, output } = p.redemptionUtxo;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      redemptionRedeemerToData({
        variant: "SweepResidual",
        outputIndex: p.outputIndex,
      }),
    )
    .txInScript(script.code);

  p.txBuilder.readOnlyTxInReference(
    p.outcomeUtxo.input.txHash,
    p.outcomeUtxo.input.outputIndex,
  );

  const filtered = output.amount.filter((a) => BigInt(a.quantity) > 0n);
  if (filtered.length > 0) {
    p.txBuilder.txOut(p.marketAddress, filtered);
  }

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

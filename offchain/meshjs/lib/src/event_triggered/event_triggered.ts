/**
 * Transaction builders for the event-triggered assets (tokenized bond)
 * substandard (MeshJS) — docs/event-triggered-assets/spec.md.
 *
 * The instrument ships five validators, four of which are withdraw-0 stake
 * scripts exercised standalone via reward withdrawals. The core CIP-113 base
 * (PLB, `issuance_mint`, registry handlers) lives outside this repo, so the
 * builders wire the substandard's own scripts directly, with stand-ins:
 *
 *   - `cipPolicy`      stand-in for the core `issuance_mint` policy (mints the
 *                      principal and the CIP-68 reference);
 *   - `nodePolicy`     stand-in for the core registry node-NFT policy;
 *   - `plbScript`      stand-in for the programmable-logic base's custody
 *                      validator: the principal is custodied at an address whose
 *                      payment credential is this (always-approving) script and
 *                      whose stake credential is the owner's — so a third party
 *                      can spend it without the owner's key, mirroring §4.5's
 *                      permissionless path.
 *
 * Builders:
 *   - `buildRegisterAndIssueTx`  T0/T1 (§4.1): atomic register + first issue
 *   - `buildTransferTx`          T2/T2b (§4.2/§4.3): free transfer / payout-key
 *   - `buildTransformationTx`    T3 (§4.4): holder-passive value step
 *   - `buildGraduationTx`        T4 (§4.5): owner path or third-party path
 *
 * Every builder returns an unsigned transaction (hex) from a configured
 * `MeshTxBuilder`; signing and submission are the caller's wallet's business.
 */

import {
  applyParamsToScript,
  mConStr0,
  pubKeyAddress,
  resolveScriptHash,
  scriptAddress,
  serializeAddressObj,
  serializeRewardAddress,
  unixTimeToEnclosingSlot,
  type Data,
  type MeshTxBuilder,
  type Network,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import {
  issuanceCompiledCode,
  nativeMintCompiledCode,
  plutusVersion,
  thirdPartyCompiledCode,
  transferCompiledCode,
  transformationCompiledCode,
} from "./blueprint";
import {
  mintingActionToData,
  mintingParamsToData,
  moveRedeemer,
  nativeMintParamsToData,
  nativeMintRedeemer,
  referenceDatumToData,
  registryNodeToData,
  thirdPartyParamsToData,
  transferParamsToData,
  transformationParamsToData,
  updateRedeemer,
} from "./datum";
import type {
  MintingParams,
  NativeMintParams,
  ReferenceDatum,
  RegistryNode,
  Schedule,
  ThirdPartyParams,
  TransferParams,
  TransformationParams,
} from "./types";

const MIN_ADA = 2_000_000n;

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

function applyParams(code: string, params: Data[]): PlutusScript {
  return {
    code: applyParamsToScript(code, params, "Mesh"),
    version: plutusVersion,
  };
}

// -------------------------------------------------------------- script setup

export function issuanceScript(p: MintingParams): PlutusScript {
  return applyParams(issuanceCompiledCode, mintingParamsToData(p));
}

export function transferScript(p: TransferParams): PlutusScript {
  return applyParams(transferCompiledCode, transferParamsToData(p));
}

export function thirdPartyScript(p: ThirdPartyParams): PlutusScript {
  return applyParams(thirdPartyCompiledCode, thirdPartyParamsToData(p));
}

export function transformationScript(p: TransformationParams): PlutusScript {
  return applyParams(transformationCompiledCode, transformationParamsToData(p));
}

export function nativeMintPolicyScript(p: NativeMintParams): PlutusScript {
  return applyParams(nativeMintCompiledCode, nativeMintParamsToData(p));
}

/** Blake2b-224 hash of an (already parameterized) script. */
export function scriptHashOf(script: PlutusScript): string {
  return resolveScriptHash(script.code, script.version);
}

/** Policy id of a mint policy — its script hash. */
export const policyIdOf = scriptHashOf;

/** Reward (stake) address of a stake script, for its withdraw-0. */
export function stakeAddressOf(script: PlutusScript, networkId: 0 | 1): string {
  return serializeRewardAddress(scriptHashOf(script), true, networkId);
}

/**
 * The address the reference token lives at: a base address whose payment
 * credential is `paymentKeyHash` and whose stake credential is the
 * transformation script. The payment part must be a key so the transformation
 * can spend it; the stake part is what §4.4's withdraw-0 owns.
 */
export function referenceTokenAddress(
  paymentKeyHash: string,
  transformation: PlutusScript,
  networkId: 0 | 1,
): string {
  return serializeAddressObj(
    pubKeyAddress(paymentKeyHash, scriptHashOf(transformation), true),
    networkId,
  );
}

/**
 * The programmable-logic-base stand-in address that a principal token is
 * custodied at: payment credential is the (always-approving) `plbScriptHash`,
 * stake credential is the owner's key hash. Ownership rides the stake
 * credential; anyone can spend via the PLB script.
 */
export function plbScriptAddress(
  plbScriptHash: string,
  ownerStakeKeyHash: string,
  networkId: 0 | 1,
): string {
  return serializeAddressObj(
    scriptAddress(plbScriptHash, ownerStakeKeyHash, false),
    networkId,
  );
}

/** Wire a withdraw-0 gate: a zero-ada reward withdrawal running `script`. */
function applyGate(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  redeemer: Data,
  networkId: 0 | 1,
): void {
  txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(stakeAddressOf(script, networkId), "0")
    .withdrawalScript(script.code)
    .withdrawalRedeemerValue(redeemer);
}

/** Spend a PLB-custodied UTxO by running the (always-approving) PLB script. */
function spendPlbInput(
  txBuilder: MeshTxBuilder,
  utxo: UTxO,
  plbScript: PlutusScript,
): void {
  const b = txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      utxo.input.txHash,
      utxo.input.outputIndex,
      utxo.output.amount,
      utxo.output.address,
    );
  if (utxo.output.plutusData !== undefined) {
    b.txInInlineDatumPresent();
  }
  b.txInRedeemerValue(mConStr0([])).txInScript(plbScript.code);
}

function splitUnit(unit: string): { policyId: string; assetName: string } {
  return { policyId: unit.slice(0, 56), assetName: unit.slice(56) };
}

// -------------------------------------------------- RegisterAndIssue (T0/T1)

export interface RegisterAndIssueTxParams {
  txBuilder: MeshTxBuilder;
  issuance: PlutusScript;
  /** Stand-in for the core `issuance_mint` policy (the governed cip policy). */
  cipPolicy: PlutusScript;
  /** Stand-in for the core registry node-NFT policy. */
  nodePolicy: PlutusScript;
  transferLogic: PlutusScript;
  thirdPartyLogic: PlutusScript;
  transformationScript: PlutusScript;
  principalName: string;
  referenceName: string;
  schedule: Schedule;
  scale: number;
  quantity: bigint;
  nodeAddress: string;
  /** Principal custody: the beneficiary's PLB-stand-in address. */
  beneficiaryAddress: string;
  /** Payment key hash of the beneficiary — the reference token address's
   * payment credential, so the beneficiary can spend it (§4.4). */
  beneficiaryKeyHash: string;
  issuer: Parameters<typeof applyAuthorization>[1];
  authorizer?: ScriptAuthorizer;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * Build the atomic register + first-issue transaction (§4.1): create the
 * RegistryNode, mint the first batch (principal + CIP-68 reference), place the
 * principal at the beneficiary's PLB stand-in, and the reference token at the
 * transformation script's stake credential.
 */
export async function buildRegisterAndIssueTx(
  p: RegisterAndIssueTxParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const cipPolicyId = policyIdOf(p.cipPolicy);
  const nodePolicyId = policyIdOf(p.nodePolicy);

  const nodeDatum: RegistryNode = {
    key: cipPolicyId,
    next: cipPolicyId,
    mintingLogic: { kind: "script", hash: scriptHashOf(p.issuance) },
    transferLogic: { kind: "script", hash: scriptHashOf(p.transferLogic) },
    thirdPartyLogic: { kind: "script", hash: scriptHashOf(p.thirdPartyLogic) },
    unfrackingLogic: null,
    globalStateCs: "",
  };

  const refDatum: ReferenceDatum = {
    metadata: "",
    version: 1,
    extra: { schedule: p.schedule, value: p.scale },
  };

  const referenceAddress = referenceTokenAddress(
    p.beneficiaryKeyHash,
    p.transformationScript,
    networkId,
  );

  const quantity = p.quantity;

  applyAuthorization(p.txBuilder, p.issuer, p.authorizer, networkId);

  const builder = p.txBuilder
    .mintPlutusScriptV3()
    .mint(quantity.toString(), cipPolicyId, p.principalName)
    .mint("1", cipPolicyId, p.referenceName)
    .mintRedeemerValue(mConStr0([]))
    .mintingScript(p.cipPolicy.code)
    .mintPlutusScriptV3()
    .mint("1", nodePolicyId, cipPolicyId)
    .mintRedeemerValue(mConStr0([]))
    .mintingScript(p.nodePolicy.code)
    .withdrawalPlutusScriptV3()
    .withdrawal(stakeAddressOf(p.issuance, networkId), "0")
    .withdrawalScript(p.issuance.code)
    .withdrawalRedeemerValue(mintingActionToData("RegisterAndMint"))
    .txOut(p.nodeAddress, [
      { unit: "lovelace", quantity: MIN_ADA.toString() },
      { unit: nodePolicyId + cipPolicyId, quantity: "1" },
    ])
    .txOutInlineDatumValue(registryNodeToData(nodeDatum))
    .txOut(p.beneficiaryAddress, [
      { unit: "lovelace", quantity: MIN_ADA.toString() },
      { unit: cipPolicyId + p.principalName, quantity: quantity.toString() },
    ])
    .txOut(referenceAddress, [
      { unit: "lovelace", quantity: MIN_ADA.toString() },
      { unit: cipPolicyId + p.referenceName, quantity: "1" },
    ])
    .txOutInlineDatumValue(referenceDatumToData(refDatum));

  return await builder
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

// ----------------------------------------------------- Transfer (T2 / T2b)

export interface TransferTxParams {
  txBuilder: MeshTxBuilder;
  transfer: PlutusScript;
  /** The PLB stand-in script custodies the principal (always-approving). */
  plbScript: PlutusScript;
  principalUtxo: UTxO;
  /** The recipient's PLB-stand-in address (same for a T2b self-transfer). */
  recipientAddress: string;
  /** Optional inline datum on the continuation (§4.3 payout key). */
  datum?: Data;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * Build a free transfer (§4.2), or the payout-key self-transfer (§4.3) when
 * `datum` carries a `PrincipalDatum` commitment. The transfer logic is
 * permissive; the withdraw-0 just runs.
 */
export async function buildTransferTx(p: TransferTxParams): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const { output } = p.principalUtxo;

  applyGate(p.txBuilder, p.transfer, moveRedeemer(), networkId);
  spendPlbInput(p.txBuilder, p.principalUtxo, p.plbScript);

  const builder = p.txBuilder.txOut(p.recipientAddress, output.amount);

  if (p.datum !== undefined) {
    builder.txOutInlineDatumValue(p.datum);
  }

  return await builder
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

// --------------------------------------------------- Transformation (T3)

export interface TransformationTxParams {
  txBuilder: MeshTxBuilder;
  transformation: PlutusScript;
  referenceUtxo: UTxO;
  /** Preserved CIP-68 metadata (the datum is rewritten in place). */
  metadata: Data;
  schedule: Schedule;
  /** The recorded value to write: `lookup(schedule, now)`. */
  nextValue: number;
  /** POSIX ms used as the validity-range lower bound. */
  now: number;
  slotConfig: SlotConfig;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * Build the scheduled transformation (§4.4): rewrite the reference token's
 * datum in place, its recorded value stepping to the current schedule step.
 * The reference token's payment credential is a key, so the beneficiary signs
 * to spend it; the transformation gate runs as a withdraw-0.
 */
export async function buildTransformationTx(
  p: TransformationTxParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const { input, output } = p.referenceUtxo;

  const nextDatum: ReferenceDatum = {
    metadata: p.metadata,
    version: 1,
    extra: { schedule: p.schedule, value: p.nextValue },
  };

  applyGate(p.txBuilder, p.transformation, updateRedeemer(), networkId);

  return await p.txBuilder
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txOut(output.address, output.amount)
    .txOutInlineDatumValue(referenceDatumToData(nextDatum))
    .invalidBefore(unixTimeToEnclosingSlot(p.now, p.slotConfig))
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

// -------------------------------------------------------- Graduation (T4)

export interface GraduationTxParams {
  txBuilder: MeshTxBuilder;
  issuance: PlutusScript;
  cipPolicy: PlutusScript;
  nativeMint: PlutusScript;
  /** The PLB stand-in script custodies the principal (always-approving). */
  plbScript: PlutusScript;
  /** Unit (policyId + assetName, hex) of the principal token to burn. */
  principalUnit: string;
  principalQuantity: bigint;
  /** Unit of the graduated asset to mint (same name, native policy). */
  nativeUnit: string;
  nativeQuantity: bigint;
  /** PLB-custodied UTxOs holding the principal to burn (whole holdings). */
  principalInputs: UTxO[];
  /** Destination of the graduated asset. */
  nativeOutputAddress: string;
  /** Owner path: the owner's stake-key hash as a required signer (Q-GRAD-2).
   * Omit for the third-party path (the committed payment credential binds). */
  ownerSigner?: string;
  /** POSIX ms used as the validity-range lower bound (must reach `d4`). */
  now: number;
  slotConfig: SlotConfig;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * Build a graduation (§4.5): burn the principal and mint the graduated asset
 * under the (real) native policy, gated to `d4`. Two spend paths share the
 * burn; select with `ownerSigner`.
 */
export async function buildGraduationTx(
  p: GraduationTxParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const { policyId: cipPolicyId, assetName: principalName } = splitUnit(
    p.principalUnit,
  );
  const { policyId: nativePolicyId, assetName: nativeName } = splitUnit(
    p.nativeUnit,
  );

  applyGate(p.txBuilder, p.issuance, mintingActionToData("Burn"), networkId);

  let builder = p.txBuilder
    .mintPlutusScriptV3()
    .mint("-" + p.principalQuantity.toString(), cipPolicyId, principalName)
    .mintRedeemerValue(mConStr0([]))
    .mintingScript(p.cipPolicy.code)
    .mintPlutusScriptV3()
    .mint(p.nativeQuantity.toString(), nativePolicyId, nativeName)
    .mintRedeemerValue(nativeMintRedeemer())
    .mintingScript(p.nativeMint.code);

  for (const holder of p.principalInputs) {
    spendPlbInput(builder, holder, p.plbScript);
  }

  builder = builder.txOut(p.nativeOutputAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    { unit: p.nativeUnit, quantity: p.nativeQuantity.toString() },
  ]);

  if (p.ownerSigner !== undefined) {
    builder = builder.requiredSignerHash(p.ownerSigner);
  }

  return await builder
    .invalidBefore(unixTimeToEnclosingSlot(p.now, p.slotConfig))
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

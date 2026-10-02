/**
 * Composed CIP-113 transactions for the tokenized bond over the real core
 * deployment: PLB spends (`BaseSpendRedeemer`), the dispatcher/delegate
 * withdraw chains, `issuance_mint` (the bond policy) and the module's own
 * withdraw-0s.
 *
 * Index discipline: `reference_inputs` are sorted canonically and
 * `withdrawals` in ledger order; every `params_idx`/`node_idx`/`wdrl_idx` is
 * derived from the assembled set (never read off a listing).
 */

import {
  mConStr0,
  type MeshTxBuilder,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import {
  applyAuthorization,
  credentialToData,
  issuanceScript,
  mintingActionToData,
  moveRedeemer,
  nativeMintPolicyScript,
  principalDatumToData,
  referenceDatumToData,
  registryNodeToData,
  thirdPartyScript,
  transferScript,
  transformationScript,
  updateRedeemer,
  type Credential,
  type MintingParams,
  type PrincipalDatum,
  type ReferenceDatum,
  type RegistryNode,
  type Schedule,
  type ScriptAuthorizer,
} from "@contracts-library/meshjs";

import {
  EX_UNITS,
  applyScript,
  referenceIndexOf,
  rewardAddressOf,
  scriptAddressOf,
  scriptHashOf,
  sortReferenceInputs,
  withdrawalIndexOf,
  type WithdrawalKey,
} from "./core";
import {
  baseSpendRedeemer,
  issuanceLogicRedeemer,
  issuanceMintRedeemer,
  registryInsertRedeemer,
  transferAct,
  transferRedeemer,
} from "./data";
import { issuanceMintCompiledCode } from "./blueprint";
import type { Deployment } from "./deploy";

const MIN_ADA = 2_000_000n;
const SENTINEL_NEXT = "ff".repeat(30);
const EMPTY_VKEY: Credential = { kind: "key", hash: "" };

export interface BondConfig {
  principalName: string;
  referenceName: string;
  schedule: Schedule;
  scale: number;
  issuer: Credential;
}

export interface Bond {
  config: BondConfig;
  finalDeadline: number;
  issuance: PlutusScript;
  issuanceMint: PlutusScript;
  policyId: string;
  transfer: PlutusScript;
  thirdParty: PlutusScript;
  transformation: PlutusScript;
  nativeMint: PlutusScript;
  nativePolicyId: string;
  /** Credentials to register (publish consent) before use. */
  withdrawCredentials: PlutusScript[];
}

export function applyBond(deployment: Deployment, config: BondConfig): Bond {
  const { core } = deployment;
  const finalDeadline = config.schedule[config.schedule.length - 1].deadline;

  const transfer = transferScript({
    registryNodeCs: core.registryNodeCs,
    finalDeadline,
  });
  const thirdParty = thirdPartyScript({
    registryNodeCs: core.registryNodeCs,
    finalDeadline,
  });
  const transformation = transformationScript({
    referenceName: config.referenceName,
    schedule: config.schedule,
  });

  const mintingParams: MintingParams = {
    registryNodeCs: core.registryNodeCs,
    issuer: config.issuer,
    transferLogic: scriptHashOf(transfer),
    thirdPartyLogic: scriptHashOf(thirdParty),
    transformationScript: scriptHashOf(transformation),
    principalName: config.principalName,
    referenceName: config.referenceName,
    schedule: config.schedule,
    scale: config.scale,
  };
  const issuance = issuanceScript(mintingParams);

  const issuanceMint = applyScript(issuanceMintCompiledCode, [
    credentialToData({ kind: "script", hash: scriptHashOf(issuance) }),
    core.paramsPolicy,
  ]);
  const policyId = scriptHashOf(issuanceMint);

  const nativeMint = nativeMintPolicyScript({
    cipPolicy: policyId,
    principalName: config.principalName,
    scale: config.scale,
    schedule: config.schedule,
  });

  return {
    config,
    finalDeadline,
    issuance,
    issuanceMint,
    policyId,
    transfer,
    thirdParty,
    transformation,
    nativeMint,
    nativePolicyId: scriptHashOf(nativeMint),
    withdrawCredentials: [issuance, transfer, thirdParty, transformation],
  };
}

// ----------------------------------------------------------------- helpers

function plbHash(d: Deployment): string {
  return scriptHashOf(d.core.programmableLogicBase);
}

export function plbAddress(
  d: Deployment,
  stakeHash: string,
  isStakeScript: boolean,
): string {
  return scriptAddressOf(plbHash(d), d.config.networkId, {
    hash: stakeHash,
    isScript: isStakeScript,
  });
}

function w0(
  tb: MeshTxBuilder,
  d: Deployment,
  script: PlutusScript,
  redeemer: unknown,
): void {
  tb.withdrawalPlutusScriptV3()
    .withdrawal(rewardAddressOf(scriptHashOf(script), d.config.networkId), "0")
    .withdrawalScript(script.code)
    .withdrawalRedeemerValue(redeemer as never, "Mesh", EX_UNITS);
}

function wdrlIdxOf(d: Deployment, scripts: PlutusScript[]): number {
  const all: WithdrawalKey[] = scripts.map((s) => ({
    hash: scriptHashOf(s),
    isScript: true,
  }));
  return withdrawalIndexOf(all, {
    hash: d.core.programmableLogicGlobalHash,
    isScript: true,
  });
}

interface Base {
  txBuilder: MeshTxBuilder;
  deployment: Deployment;
  funding: UTxO[];
  collateral: UTxO;
  changeAddress: string;
}

async function complete(base: Base, extraRefs: UTxO[] = []): Promise<string> {
  for (const ref of extraRefs) {
    base.txBuilder.readOnlyTxInReference(
      ref.input.txHash,
      ref.input.outputIndex,
    );
  }
  const tx = await base.txBuilder
    .txInCollateral(
      base.collateral.input.txHash,
      base.collateral.input.outputIndex,
      base.collateral.output.amount,
      base.collateral.output.address,
    )
    .changeAddress(base.changeAddress)
    .selectUtxosFrom(base.funding)
    .complete();
  return tx;
}

// ---------------------------------------------------------- register + issue

export interface RegisterAndIssueParams extends Base {
  bond: Bond;
  covering: UTxO;
  coveringNode: RegistryNode;
  quantity: bigint;
  beneficiaryAddress: string;
  referenceAddress: string;
  nodeAddress: string;
  /** How to satisfy a script `issuer` credential (ignored for a key). */
  authorizer?: ScriptAuthorizer;
}

export async function buildRegisterAndIssue(
  p: RegisterAndIssueParams,
): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  // Registration authority: a key issuer is declared (and signed at submit),
  // a script issuer is invoked via withdraw-0.
  applyAuthorization(tb, b.config.issuer, p.authorizer, d.config.networkId);

  const refs = sortReferenceInputs([d.refs.protocolParams, d.refs.cborHex]);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);

  // Outputs: [0] updated covering node, [1] new bond node — the issuance_logic
  // OutputIndex proof names the new node output (index 1).
  const newNodeIdx = 1;

  // Spend the covering registry node (registry spend handler, void redeemer).
  tb.inputForEvaluation(p.covering);
  tb.spendingPlutusScriptV3()
    .txIn(
      p.covering.input.txHash,
      p.covering.input.outputIndex,
      p.covering.output.amount,
      p.covering.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(mConStr0([]), "Mesh", EX_UNITS)
    .txInScript(d.core.registry.code);

  // Registry node NFT mint (RegistryInsert), then the bond's first batch.
  tb.mintPlutusScriptV3()
    .mint("1", d.core.registryNodeCs, b.policyId)
    .mintRedeemerValue(
      registryInsertRedeemer(b.policyId, {
        kind: "script",
        hash: scriptHashOf(b.issuance),
      }),
      "Mesh",
      EX_UNITS,
    )
    .mintingScript(d.core.registry.code)
    .mintPlutusScriptV3()
    .mint(p.quantity.toString(), b.policyId, b.config.principalName)
    .mintRedeemerValue(issuanceMintRedeemer(paramsIdx), "Mesh", EX_UNITS)
    .mintingScript(b.issuanceMint.code)
    .mintPlutusScriptV3()
    .mint("1", b.policyId, b.config.referenceName)
    .mintRedeemerValue(issuanceMintRedeemer(paramsIdx), "Mesh", EX_UNITS)
    .mintingScript(b.issuanceMint.code);

  // Withdraw-0s: our issuance logic (RegisterAndMint) + protocol issuance_logic
  // (its redeemer keys the bond policy, OutputIndex → the new node output).
  w0(tb, d, b.issuance, mintingActionToData("RegisterAndMint"));
  w0(
    tb,
    d,
    d.core.issuanceLogic,
    issuanceLogicRedeemer([{ policy: b.policyId, index: newNodeIdx }]),
  );

  const refDatum: ReferenceDatum = {
    metadata: "",
    version: 1,
    extra: {
      schedule: b.config.schedule,
      value: b.config.scale,
      nativePolicy: b.nativePolicyId,
    },
  };

  tb.txOut(p.nodeAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    { unit: d.core.registryNodeCs + p.coveringNode.key, quantity: "1" },
  ]);
  tb.txOutInlineDatumValue(
    registryNodeToData({ ...p.coveringNode, next: b.policyId }),
  );

  tb.txOut(p.nodeAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    { unit: d.core.registryNodeCs + b.policyId, quantity: "1" },
  ]);
  tb.txOutInlineDatumValue(
    registryNodeToData({
      key: b.policyId,
      next: SENTINEL_NEXT,
      mintingLogic: { kind: "script", hash: scriptHashOf(b.issuance) },
      transferLogic: { kind: "script", hash: scriptHashOf(b.transfer) },
      thirdPartyLogic: { kind: "script", hash: scriptHashOf(b.thirdParty) },
      unfrackingLogic: EMPTY_VKEY,
      globalStateCs: "",
    }),
  );

  tb.txOut(p.beneficiaryAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    {
      unit: b.policyId + b.config.principalName,
      quantity: p.quantity.toString(),
    },
  ]);

  tb.txOut(p.referenceAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    { unit: b.policyId + b.config.referenceName, quantity: "1" },
  ]);
  tb.txOutInlineDatumValue(referenceDatumToData(refDatum));

  return complete(p, refs);
}

// ---------------------------------------------------------------- transfer

export interface TransferParams extends Base {
  bond: Bond;
  node: UTxO;
  principalInputs: UTxO[];
  recipientAddress: string;
  senderStakeHash: string;
  datum?: PrincipalDatum;
}

export async function buildTransfer(p: TransferParams): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const refs = sortReferenceInputs([d.refs.protocolParams, p.node]);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [d.core.programmableLogicGlobal, d.core.transfer, b.transfer];
  // The transfer's withdrawals are exactly this chain.
  const wdrlIdx = wdrlIdxOf(d, chain);

  for (const input of p.principalInputs) {
    tb.inputForEvaluation(input);
    const s = tb
      .spendingPlutusScriptV3()
      .txIn(
        input.input.txHash,
        input.input.outputIndex,
        input.output.amount,
        input.output.address,
      );
    s.txInInlineDatumPresent();
    s.txInRedeemerValue(
      baseSpendRedeemer(paramsIdx, wdrlIdx),
      "Mesh",
      EX_UNITS,
    ).txInScript(d.core.programmableLogicBase.code);
  }

  w0(tb, d, d.core.programmableLogicGlobal, transferAct());
  w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
  w0(tb, d, b.transfer, moveRedeemer());
  tb.requiredSignerHash(p.senderStakeHash);

  const assets = p.principalInputs.flatMap((u) => u.output.amount);
  tb.txOut(p.recipientAddress, assets);
  if (p.datum !== undefined) {
    tb.txOutInlineDatumValue(principalDatumToData(p.datum));
  }

  return complete(p, refs);
}

// ----------------------------------------------------------------- transform

export interface TransformParams extends Base {
  bond: Bond;
  node: UTxO;
  referenceUtxo: UTxO;
  nextValue: number;
  validFromSlot: number;
}

export async function buildTransform(p: TransformParams): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const refs = sortReferenceInputs([d.refs.protocolParams, p.node]);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [
    d.core.programmableLogicGlobal,
    d.core.transfer,
    b.transfer,
    b.transformation,
  ];
  // The PLB redeemer's `wdrl_idx` names PLG's position in the transaction's
  // FULL withdrawal set, not just the transfer chain.
  const wdrlIdx = wdrlIdxOf(d, chain);

  tb.inputForEvaluation(p.referenceUtxo);
  tb.spendingPlutusScriptV3()
    .txIn(
      p.referenceUtxo.input.txHash,
      p.referenceUtxo.input.outputIndex,
      p.referenceUtxo.output.amount,
      p.referenceUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(baseSpendRedeemer(paramsIdx, wdrlIdx), "Mesh", EX_UNITS)
    .txInScript(d.core.programmableLogicBase.code);

  w0(tb, d, d.core.programmableLogicGlobal, transferAct());
  w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
  w0(tb, d, b.transfer, moveRedeemer());
  w0(tb, d, b.transformation, updateRedeemer());

  tb.txOut(p.referenceUtxo.output.address, p.referenceUtxo.output.amount);
  tb.txOutInlineDatumValue(
    referenceDatumToData({
      metadata: "",
      version: 1,
      extra: {
        schedule: b.config.schedule,
        value: p.nextValue,
        nativePolicy: b.nativePolicyId,
      },
    }),
  );

  tb.invalidBefore(p.validFromSlot);
  return complete(p, refs);
}

// ---------------------------------------------------------------- graduate

export interface GraduateParams extends Base {
  bond: Bond;
  node: UTxO;
  referenceUtxo: UTxO;
  principalInputs: UTxO[];
  principalQuantity: bigint;
  nativeQuantity: bigint;
  nativeOutputAddress: string;
  ownerStakeHash: string;
  validFromSlot: number;
}

export async function buildGraduateOwner(p: GraduateParams): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const refs = sortReferenceInputs([
    d.refs.protocolParams,
    p.node,
    p.referenceUtxo,
  ]);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [d.core.programmableLogicGlobal, d.core.transfer, b.transfer];
  // The burn's two withdraw-0s (module issuance + core issuance logic) join
  // the transfer chain, and the PLB redeemer's `wdrl_idx` must index the
  // full, canonically ordered withdrawal set.
  const wdrlIdx = wdrlIdxOf(d, [...chain, b.issuance, d.core.issuanceLogic]);

  for (const input of p.principalInputs) {
    tb.inputForEvaluation(input);
    const s = tb
      .spendingPlutusScriptV3()
      .txIn(
        input.input.txHash,
        input.input.outputIndex,
        input.output.amount,
        input.output.address,
      );
    s.txInInlineDatumPresent();
    s.txInRedeemerValue(
      baseSpendRedeemer(paramsIdx, wdrlIdx),
      "Mesh",
      EX_UNITS,
    ).txInScript(d.core.programmableLogicBase.code);
  }

  // Burn the principal under issuance_mint, mint the native asset.
  tb.mintPlutusScriptV3()
    .mint(
      "-" + p.principalQuantity.toString(),
      b.policyId,
      b.config.principalName,
    )
    .mintRedeemerValue(issuanceMintRedeemer(paramsIdx), "Mesh", EX_UNITS)
    .mintingScript(b.issuanceMint.code)
    .mintPlutusScriptV3()
    .mint(p.nativeQuantity.toString(), b.nativePolicyId, b.config.principalName)
    .mintRedeemerValue(mConStr0([]), "Mesh", EX_UNITS)
    .mintingScript(b.nativeMint.code);

  w0(tb, d, d.core.programmableLogicGlobal, transferAct());
  w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
  w0(tb, d, b.transfer, moveRedeemer());
  w0(tb, d, b.issuance, mintingActionToData("Burn"));
  w0(
    tb,
    d,
    d.core.issuanceLogic,
    issuanceLogicRedeemer([
      { policy: b.policyId, index: nodeIdx, proof: "ref" },
    ]),
  );

  tb.txOut(p.nativeOutputAddress, [
    { unit: "lovelace", quantity: MIN_ADA.toString() },
    {
      unit: b.nativePolicyId + b.config.principalName,
      quantity: p.nativeQuantity.toString(),
    },
  ]);
  tb.requiredSignerHash(p.ownerStakeHash);
  tb.invalidBefore(p.validFromSlot);

  return complete(p, refs);
}

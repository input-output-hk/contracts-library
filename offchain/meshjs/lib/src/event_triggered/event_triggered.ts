/**
 * Transaction builders for the event-triggered assets (tokenized bond)
 * substandard (MeshJS) — docs/event-triggered-assets/spec.md.
 *
 * These are **real-core** builders: they compose with a deployed CIP-113 core
 * (`CoreDeployment`: PLB, dispatcher, delegates, issuance, registry) and the
 * bond's own validators (issuance, transfer, third-party, vault, coupon policy,
 * vault NFT policy). Every transaction is built to validate against the core,
 * including the withdraw-0 chains, registry proofs and ledger index ordering
 * (`params_idx` / `node_idx` / `wdrl_idx`).
 *
 * Builders (all return an unsigned transaction hex):
 *   - `buildCreateVaultTx`      §3.1: mint the vault NFT into a funded vault
 *   - `buildRegisterTx`         §4.1: registry insert (no certificate)
 *   - `buildBondDepositTx`      §4.2: unit deposit → certificate (step 0)
 *   - `buildTransferTx`         §4.3: plain transfer / owner change
 *   - `buildAuthorizeTx`        §4.4: self-transfer committing a payout credit
 *   - `buildClaimOwnerTx`       §4.5: owner-signed coupon claim (advance)
 *   - `buildClaimIssuerTx`      §4.5: issuer-triggered claim (third party)
 *   - `buildRedeemTx`           §4.6: burn-to-pay at the vault
 *   - `buildGraduateOwnerTx`    §4.7: owner-signed retirement + principal coupon
 *   - `buildGraduateIssuerTx`   §4.7: issuer-triggered retirement (third party)
 */

import {
  applyParamsToScript,
  type Asset,
  type Data,
  type MeshTxBuilder,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import {
  applyAuthorization,
  authorizerReference,
  authorizerScriptHash,
  type ScriptAuthorizer,
} from "../authorization";
import { credentialToData, finalizeTx, type Credential } from "../common";
import {
  baseSpendRedeemer,
  EX_UNITS,
  issuanceLogicRedeemer,
  issuanceMintRedeemer,
  cip113PlutusVersion,
  referenceIndexOf,
  registryInsertRedeemer,
  rewardAddressOf,
  scriptAddressOf,
  scriptHashOf,
  sortReferenceInputs,
  thirdPartyAct,
  thirdPartyRedeemer,
  transferAct,
  transferRedeemer,
  withdrawalIndexOf,
  type CoreDeployment,
  type WithdrawalKey,
} from "../cip113";
import {
  couponPolicyCompiledCode,
  issuanceCompiledCode,
  thirdPartyCompiledCode,
  transferCompiledCode,
  vaultCompiledCode,
  vaultNftPolicyCompiledCode,
} from "./blueprint";
import {
  certificateDatumToData,
  couponName,
  decodeCouponName,
  mintingActionToData,
  mintingParamsToData,
  moveRedeemer,
  redeemRedeemer,
  registryNodeToData,
  stepName,
  thirdPartyParamsToData,
  transferParamsToData,
  triggerRedeemer,
  unitRedeemer,
  vaultDatumToData,
  vaultDepositRedeemer,
  vaultTopUpRedeemer,
  vaultNftParamsToData,
  vaultParamsToData,
  couponParamsToData,
} from "./datum";
import type {
  Bond,
  BondConfig,
  CertificateDatum,
  CouponParams,
  MintingParams,
  Payout,
  RegistryNode,
  ThirdPartyParams,
  TransferParams,
  VaultDatum,
  VaultNftParams,
  VaultParams,
} from "./types";

const MIN_ADA = 2_000_000n;
const EMPTY_VKEY = { kind: "key" as const, hash: "" };

function applyParams(code: string, params: Data[]): PlutusScript {
  const applied = applyParamsToScript(code, params, "Mesh") as string;
  return { code: applied, version: cip113PlutusVersion };
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

export function vaultScript(p: VaultParams): PlutusScript {
  return applyParams(vaultCompiledCode, vaultParamsToData(p));
}

export function couponPolicyScript(p: CouponParams): PlutusScript {
  return applyParams(couponPolicyCompiledCode, couponParamsToData(p));
}

export function vaultNftPolicyScript(p: VaultNftParams): PlutusScript {
  return applyParams(vaultNftPolicyCompiledCode, vaultNftParamsToData(p));
}

// ------------------------------------------------------------ bond assembly

/** Asset names are at most 32 bytes (64 hex chars). */
const MAX_ASSET_NAME_BYTES = 32;

function isPositiveInt(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

/** A non-empty, even-length hex string of at most 32 bytes. */
function isValidAssetName(name: string): boolean {
  return (
    name.length > 0 &&
    name.length <= MAX_ASSET_NAME_BYTES * 2 &&
    name.length % 2 === 0 &&
    /^[0-9a-fA-F]+$/.test(name)
  );
}

/** The byte length of a coupon asset name (the decimal bytes of `amount`). */
function couponNameBytes(amount: number): number {
  return Buffer.byteLength(amount.toString(), "utf8");
}

/**
 * Refuse configurations the validators cannot honor, before any parameter is
 * applied: a non-positive or fractional principal/interval, an empty or
 * over-long schedule, non-positive coupon amounts, coupon names over 32 bytes,
 * or a vault NFT name over 32 bytes. Steps past 255 can never be reached (the
 * certificate step is one byte), so at most 255 steps are admitted.
 */
function validateBondConfig(config: BondConfig): void {
  if (!isPositiveInt(config.principal)) {
    throw new Error(
      `Bond principal must be a positive integer, got ${config.principal}.`,
    );
  }
  if (!isPositiveInt(config.interval)) {
    throw new Error(
      `Bond interval must be a positive integer, got ${config.interval}.`,
    );
  }
  if (config.amounts.length === 0) {
    throw new Error("Bond schedule must have at least one step.");
  }
  if (config.amounts.length > 255) {
    throw new Error(
      `Bond schedule has ${config.amounts.length} steps; the certificate step ` +
        `is one byte, so at most 255 are reachable.`,
    );
  }
  for (const amount of config.amounts) {
    if (!isPositiveInt(amount)) {
      throw new Error(
        `Coupon amounts must be positive integers, got ${amount}.`,
      );
    }
  }
  for (const amount of [config.principal, ...config.amounts]) {
    if (couponNameBytes(amount) > MAX_ASSET_NAME_BYTES) {
      throw new Error(
        `Coupon name for amount ${amount} exceeds the ` +
          `${MAX_ASSET_NAME_BYTES}-byte asset-name limit.`,
      );
    }
  }
  if (!isValidAssetName(config.vaultNftName)) {
    throw new Error(
      `Vault NFT name must be a non-empty hex string of at most ` +
        `${MAX_ASSET_NAME_BYTES} bytes, got "${config.vaultNftName}".`,
    );
  }
}

/**
 * Apply a bond over a core deployment, in the documented dependency order:
 * transfer / third-party / vault-NFT policy → vault → minting logic →
 * `issuance_mint` (the governed `cipPolicy`) → coupon policy (`cntPolicy`).
 */
export function applyBond(
  deployment: CoreDeployment,
  config: BondConfig,
): Bond {
  validateBondConfig(config);

  const { registryNodeCs, paramsPolicy } = deployment.core;

  const transfer = transferScript({ registryNodeCs });
  const thirdParty = thirdPartyScript({
    registryNodeCs,
    issuer: config.issuer,
  });

  const vaultNft = vaultNftPolicyScript({
    authority: config.authority ?? config.issuer,
  });
  const vaultNftCs = scriptHashOf(vaultNft);

  const vault = vaultScript({
    principal: config.principal,
    vaultNftCs,
  });
  const vaultHash = scriptHashOf(vault);

  const issuance = issuanceScript({
    registryNodeCs,
    issuer: config.issuer,
    transferLogic: scriptHashOf(transfer),
    thirdPartyLogic: scriptHashOf(thirdParty),
    vault: vaultHash,
    vaultNftCs,
    principal: config.principal,
  });
  const issuanceMint = applyParams(deployment.issuanceMintCode, [
    credentialToData({ kind: "script", hash: scriptHashOf(issuance) }),
    paramsPolicy,
  ]);
  const cipPolicy = scriptHashOf(issuanceMint);

  const couponPolicy = couponPolicyScript({
    cipPolicy,
    principal: config.principal,
    interval: config.interval,
    amounts: config.amounts,
  });
  const cntPolicy = scriptHashOf(couponPolicy);

  return {
    config,
    networkId: deployment.config.networkId,
    transfer,
    thirdParty,
    issuance,
    issuanceMint,
    cipPolicy,
    vaultNft,
    vaultNftCs,
    vault,
    vaultHash,
    couponPolicy,
    cntPolicy,
    withdrawCredentials: [issuance, transfer, thirdParty],
  };
}

// ---------------------------------------------------------------- addresses

/** The PLB-custodied certificate address: PLB payment + the holder's stake. */
export function plbAddress(
  deployment: CoreDeployment,
  stakeHash: string,
  isStakeScript = false,
): string {
  return scriptAddressOf(
    scriptHashOf(deployment.core.programmableLogicBase),
    deployment.config.networkId,
    { hash: stakeHash, isScript: isStakeScript },
  );
}

/** The vault script address of this bond. */
export function vaultAddress(bond: Bond): string {
  return scriptAddressOf(bond.vaultHash, bond.networkId);
}

/** The registry node address of the core deployment. */
export function nodeAddress(deployment: CoreDeployment): string {
  return scriptAddressOf(
    deployment.core.registryNodeCs,
    deployment.config.networkId,
  );
}

// ----------------------------------------------------------------- plumbing

export interface TxBase {
  txBuilder: MeshTxBuilder;
  deployment: CoreDeployment;
  funding: UTxO[];
  collateral: UTxO;
  changeAddress: string;
}

async function complete(base: TxBase, refs: UTxO[] = []): Promise<string> {
  for (const ref of refs) {
    base.txBuilder.readOnlyTxInReference(
      ref.input.txHash,
      ref.input.outputIndex,
    );
  }
  return finalizeTx(base.txBuilder, {
    collateral: base.collateral,
    changeAddress: base.changeAddress,
    utxos: base.funding,
  });
}

/** The certificate holder's credential from its hash (+ script flag). */
function holderCredential(hash: string, isScript = false) {
  return isScript
    ? ({ kind: "script", hash } as const)
    : ({ kind: "key", hash } as const);
}

function w0(
  tb: MeshTxBuilder,
  d: CoreDeployment,
  script: PlutusScript,
  redeemer: Data,
): void {
  tb.withdrawalPlutusScriptV3()
    .withdrawal(rewardAddressOf(scriptHashOf(script), d.config.networkId), "0")
    .withdrawalScript(script.code)
    .withdrawalRedeemerValue(redeemer, "Mesh", EX_UNITS);
}

/**
 * Index of `programmable_logic_global` in the ledger's complete withdrawal
 * set. Pass every withdrawal key the transaction carries: the PLB redeemer
 * witnesses PLG's position in the full set, not just the transfer chain.
 */
function wdrlIdxOf(d: CoreDeployment, keys: WithdrawalKey[]): number {
  const unique = new Map<string, WithdrawalKey>();
  for (const key of keys) {
    unique.set(`${key.isScript}:${key.hash.toLowerCase()}`, key);
  }
  return withdrawalIndexOf([...unique.values()], {
    hash: d.core.programmableLogicGlobalHash,
    isScript: true,
  });
}

/** Withdrawal keys of the given withdraw-0 scripts. */
function withdrawalKeys(scripts: PlutusScript[]): WithdrawalKey[] {
  return scripts.map((s) => ({ hash: scriptHashOf(s), isScript: true }));
}

/**
 * The transaction's complete withdrawal set: the given chain plus the
 * authorizer's entry, when the credential is authorized by a script. The
 * ledger orders withdrawals canonically, so index-bearing redeemers must count
 * the authorizer's withdraw-0 too.
 */
function fullWithdrawalKeys(
  chain: PlutusScript[],
  credential: Credential,
  authorizer: ScriptAuthorizer | undefined,
): WithdrawalKey[] {
  const keys = withdrawalKeys(chain);
  const hash = authorizerScriptHash(credential, authorizer);
  if (hash !== undefined) keys.push({ hash, isScript: true });
  return keys;
}

/**
 * The transaction's complete reference-input set, canonically sorted,
 * including the authorizer's reference UTxO when it has one.
 */
function fullReferences(
  refs: UTxO[],
  authorizer: ScriptAuthorizer | undefined,
): UTxO[] {
  const reference = authorizerReference(authorizer);
  return sortReferenceInputs(reference ? [...refs, reference] : refs);
}

function plbSpend(
  tb: MeshTxBuilder,
  d: CoreDeployment,
  utxo: UTxO,
  paramsIdx: number,
  wdrlIdx: number,
): void {
  tb.inputForEvaluation(utxo);
  const s = tb
    .spendingPlutusScriptV3()
    .txIn(
      utxo.input.txHash,
      utxo.input.outputIndex,
      utxo.output.amount,
      utxo.output.address,
    );
  s.txInInlineDatumPresent();
  s.txInRedeemerValue(
    baseSpendRedeemer(paramsIdx, wdrlIdx),
    "Mesh",
    EX_UNITS,
  ).txInScript(d.core.programmableLogicBase.code);
}

function vaultSpend(
  tb: MeshTxBuilder,
  bond: Bond,
  utxo: UTxO,
  redeemer: Data,
): void {
  tb.inputForEvaluation(utxo);
  const s = tb
    .spendingPlutusScriptV3()
    .txIn(
      utxo.input.txHash,
      utxo.input.outputIndex,
      utxo.output.amount,
      utxo.output.address,
    );
  s.txInInlineDatumPresent();
  s.txInRedeemerValue(redeemer, "Mesh", EX_UNITS).txInScript(bond.vault.code);
}

function mintCertificate(
  tb: MeshTxBuilder,
  bond: Bond,
  paramsIdx: number,
  name: string,
  quantity: string,
): void {
  tb.mintPlutusScriptV3()
    .mint(quantity, bond.cipPolicy, name)
    .mintRedeemerValue(issuanceMintRedeemer(paramsIdx), "Mesh", EX_UNITS)
    .mintingScript(bond.issuanceMint.code);
}

function mintCoupon(
  tb: MeshTxBuilder,
  bond: Bond,
  name: string,
  quantity: string,
): void {
  tb.mintPlutusScriptV3()
    .mint(quantity, bond.cntPolicy, name)
    .mintRedeemerValue(unitRedeemer(), "Mesh", EX_UNITS)
    .mintingScript(bond.couponPolicy.code);
}

function lovelace(quantity: bigint): Asset {
  return { unit: "lovelace", quantity: quantity.toString() };
}

/** Add `delta` lovelace to an asset list (its "lovelace" entry exists). */
function addLovelace(amount: Asset[], delta: bigint): Asset[] {
  return amount.map((a) =>
    a.unit === "lovelace"
      ? { unit: a.unit, quantity: (BigInt(a.quantity) + delta).toString() }
      : a,
  );
}

/** Sum the coupon value (decode(name) × quantity) across the given UTxOs. */
function couponValue(coupons: UTxO[], cntPolicy: string): bigint {
  let total = 0n;
  for (const u of coupons) {
    for (const a of u.output.amount) {
      if (a.unit.startsWith(cntPolicy) && a.unit.length > 56) {
        const amount = decodeCouponName(a.unit.slice(56));
        total += BigInt(amount) * BigInt(a.quantity);
      }
    }
  }
  return total;
}

// ------------------------------------------------------------ create vault

export interface CreateVaultParams extends TxBase {
  bond: Bond;
  /** ADA the vault starts with (coupon reserve + deposits). */
  vaultAda: bigint;
  authorizer?: ScriptAuthorizer;
}

/** Mint the vault NFT into a newly funded vault UTxO (§3.1, I10). */
export async function buildCreateVaultTx(
  p: CreateVaultParams,
): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  applyAuthorization(
    tb,
    b.config.authority ?? b.config.issuer,
    p.authorizer,
    d.config.networkId,
  );

  tb.mintPlutusScriptV3()
    .mint("1", b.vaultNftCs, b.config.vaultNftName)
    .mintRedeemerValue(unitRedeemer(), "Mesh", EX_UNITS)
    .mintingScript(b.vaultNft.code);

  tb.txOut(vaultAddress(b), [
    lovelace(p.vaultAda),
    { unit: b.vaultNftCs + b.config.vaultNftName, quantity: "1" },
  ]);
  tb.txOutInlineDatumValue(vaultDatumToData({ cntPolicy: b.cntPolicy }));

  return complete(p);
}

// --------------------------------------------------------------- register

export interface RegisterParams extends TxBase {
  bond: Bond;
  /** The covering registry node (the origin node for the first insert). */
  covering: UTxO;
  coveringNode: RegistryNode;
  authorizer?: ScriptAuthorizer;
}

/** Registry insert (§4.1): pin the node stance; mint no certificate. */
export async function buildRegisterTx(p: RegisterParams): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  applyAuthorization(tb, b.config.issuer, p.authorizer, d.config.networkId);

  tb.inputForEvaluation(p.covering);
  tb.spendingPlutusScriptV3()
    .txIn(
      p.covering.input.txHash,
      p.covering.input.outputIndex,
      p.covering.output.amount,
      p.covering.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(unitRedeemer(), "Mesh", EX_UNITS)
    .txInScript(d.core.registry.code);

  tb.mintPlutusScriptV3()
    .mint("1", d.core.registryNodeCs, b.cipPolicy)
    .mintRedeemerValue(
      registryInsertRedeemer(b.cipPolicy, {
        kind: "script",
        hash: scriptHashOf(b.issuance),
      }),
      "Mesh",
      EX_UNITS,
    )
    .mintingScript(d.core.registry.code);

  w0(tb, d, b.issuance, mintingActionToData("Register"));

  // The covering node is re-emitted pointing at the new key, then the new node.
  const nextNode: RegistryNode = {
    key: b.cipPolicy,
    next: p.coveringNode.next,
    mintingLogic: { kind: "script", hash: scriptHashOf(b.issuance) },
    transferLogic: { kind: "script", hash: scriptHashOf(b.transfer) },
    thirdPartyLogic: { kind: "script", hash: scriptHashOf(b.thirdParty) },
    unfrackingLogic: EMPTY_VKEY,
    globalStateCs: "",
  };
  for (const node of [{ ...p.coveringNode, next: b.cipPolicy }, nextNode]) {
    tb.txOut(nodeAddress(d), [
      lovelace(MIN_ADA),
      { unit: d.core.registryNodeCs + node.key, quantity: "1" },
    ]);
    tb.txOutInlineDatumValue(registryNodeToData(node));
  }

  return complete(p, [d.refs.cborHex]);
}

// ---------------------------------------------------------------- deposit

export interface BondDepositParams extends TxBase {
  bond: Bond;
  node: UTxO;
  vault: UTxO;
  /** The certificate's stake credential (the depositor). */
  depositorStakeHash: string;
  depositorIsScript?: boolean;
  /** POSIX-ms start; must equal the upper bound of the tx validity range. */
  start: number;
  /** Slot whose validity upper bound is exactly `start`. */
  validHereafterSlot: number;
}

/** Unit deposit (§4.2): vault gains the principal; mint certificate step 0. */
export async function buildBondDepositTx(
  p: BondDepositParams,
): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const refs = sortReferenceInputs([d.refs.protocolParams, p.node]);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  vaultSpend(tb, b, p.vault, vaultDepositRedeemer());

  mintCertificate(tb, b, paramsIdx, stepName(0), "1");

  w0(tb, d, b.issuance, mintingActionToData("Deposit"));
  w0(
    tb,
    d,
    d.core.issuanceLogic,
    issuanceLogicRedeemer([
      { policy: b.cipPolicy, index: nodeIdx, proof: "ref" },
    ]),
  );

  // Vault continuation: same address/datum/NFT, +principal.
  tb.txOut(
    p.vault.output.address,
    addLovelace(p.vault.output.amount, BigInt(b.config.principal)),
  );
  tb.txOutInlineDatumValue(vaultDatumToData({ cntPolicy: b.cntPolicy }));

  const datum: CertificateDatum = {
    start: p.start,
    commit: null,
    cntPolicy: b.cntPolicy,
  };
  tb.txOut(plbAddress(d, p.depositorStakeHash, p.depositorIsScript), [
    lovelace(MIN_ADA),
    { unit: b.cipPolicy + stepName(0), quantity: "1" },
  ]);
  tb.txOutInlineDatumValue(certificateDatumToData(datum));

  tb.invalidHereafter(p.validHereafterSlot);
  return complete(p, refs);
}

// -------------------------------------------------------------- vault top-up

export interface VaultTopUpParams extends TxBase {
  bond: Bond;
  vault: UTxO;
  /** ADA added to the vault (any positive amount). */
  amount: bigint;
}

/**
 * Permissionless vault top-up (§3.1): the vault gains `amount` lovelace,
 * carrying address, datum, NFT and other assets unchanged. This is the escrow
 * funding path — there is no owner withdrawal.
 */
export async function buildVaultTopUpTx(p: VaultTopUpParams): Promise<string> {
  const { bond: b } = p;
  const tb = p.txBuilder;

  if (p.amount <= 0n) {
    throw new Error(`Vault top-up amount must be positive, got ${p.amount}.`);
  }

  vaultSpend(tb, b, p.vault, vaultTopUpRedeemer());

  tb.txOut(
    p.vault.output.address,
    addLovelace(p.vault.output.amount, p.amount),
  );
  tb.txOutInlineDatumValue(vaultDatumToData({ cntPolicy: b.cntPolicy }));

  return complete(p);
}

// ---------------------------------------------------- transfer / authorize

export interface TransferTxParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  recipientAddress: string;
  /** The continuation datum (preserved on a plain transfer). */
  outputDatum: CertificateDatum;
  holderStakeHash: string;
  holderIsScript?: boolean;
  authorizer?: ScriptAuthorizer;
}

/** Plain transfer or owner change (§4.3): name and state preserved. */
export async function buildTransferTx(p: TransferTxParams): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const holder = holderCredential(p.holderStakeHash, p.holderIsScript);
  const refs = fullReferences([d.refs.protocolParams, p.node], p.authorizer);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [d.core.programmableLogicGlobal, d.core.transfer, b.transfer];
  const wdrlIdx = wdrlIdxOf(d, fullWithdrawalKeys(chain, holder, p.authorizer));

  plbSpend(tb, d, p.certificate, paramsIdx, wdrlIdx);
  w0(tb, d, d.core.programmableLogicGlobal, transferAct());
  w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
  w0(tb, d, b.transfer, moveRedeemer());

  applyAuthorization(tb, holder, p.authorizer, d.config.networkId);

  tb.txOut(p.recipientAddress, p.certificate.output.amount);
  tb.txOutInlineDatumValue(certificateDatumToData(p.outputDatum));

  return complete(p, refs);
}

export interface AuthorizeTxParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  /** The new commitment (`Some(pay)`) — or `null` to revoke. */
  commit: CertificateDatum["commit"];
  /** The current certificate datum (the rest is preserved). */
  datum: CertificateDatum;
  holderStakeHash: string;
  holderIsScript?: boolean;
  authorizer?: ScriptAuthorizer;
}

/** Self-transfer opt-in/revoke (§4.4): same stake, `commit` written. */
export async function buildAuthorizeTx(p: AuthorizeTxParams): Promise<string> {
  return buildTransferTx({
    txBuilder: p.txBuilder,
    deployment: p.deployment,
    funding: p.funding,
    collateral: p.collateral,
    changeAddress: p.changeAddress,
    bond: p.bond,
    node: p.node,
    certificate: p.certificate,
    recipientAddress: p.certificate.output.address,
    outputDatum: { ...p.datum, commit: p.commit },
    holderStakeHash: p.holderStakeHash,
    holderIsScript: p.holderIsScript,
    authorizer: p.authorizer,
  });
}

// ------------------------------------------------------------- coupon claim

export interface ClaimOwnerParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  /** 1-indexed step `k`: the spent name is `k-1`, the continuation `k`. */
  step: number;
  /** The certificate datum to preserve. */
  datum: CertificateDatum;
  /** Where the coupon is delivered (usually the holder). */
  couponAddress: string;
  holderStakeHash: string;
  holderIsScript?: boolean;
  authorizer?: ScriptAuthorizer;
  /** Slot whose validity lower bound reaches `start + k*interval`. */
  validFromSlot: number;
}

export interface ClaimIssuerParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  step: number;
  datum: CertificateDatum;
  /** The committed payout address (payment credential = `commit`). */
  payoutAddress: string;
  authorizer?: ScriptAuthorizer;
  validFromSlot: number;
}

/**
 * The shared §4.5 claim skeleton: spend the certificate, advance `k-1 -> k`
 * plus the step's coupon, then emit the continuation and the coupon. The
 * paths differ in who signs (holder transfer vs issuer third-party) and in
 * the continuation output, which `continuation` writes.
 */
async function buildClaimTx(
  p: TxBase & {
    bond: Bond;
    node: UTxO;
    certificate: UTxO;
    step: number;
    datum: CertificateDatum;
    /** Where the minted coupon goes (holder address or committed payout). */
    couponAddress: string;
    authorizer?: ScriptAuthorizer;
    /** The owner path signs with this credential. */
    holderStakeHash?: string;
    holderIsScript?: boolean;
    validFromSlot: number;
    /** `transfer` = owner-signed; `thirdParty` = issuer-triggered. */
    kind: "transfer" | "thirdParty";
    continuation: (b: Bond) => void;
  },
): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const credential =
    p.kind === "transfer"
      ? holderCredential(p.holderStakeHash ?? "", p.holderIsScript)
      : b.config.issuer;
  const spendLogic =
    p.kind === "transfer" ? d.core.transfer : d.core.thirdParty;
  const bondLogic = p.kind === "transfer" ? b.transfer : b.thirdParty;
  const refs = fullReferences([d.refs.protocolParams, p.node], p.authorizer);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [
    d.core.programmableLogicGlobal,
    spendLogic,
    bondLogic,
    b.issuance,
    d.core.issuanceLogic,
  ];
  const wdrlIdx = wdrlIdxOf(
    d,
    fullWithdrawalKeys(chain, credential, p.authorizer),
  );

  plbSpend(tb, d, p.certificate, paramsIdx, wdrlIdx);

  mintCertificate(tb, b, paramsIdx, stepName(p.step - 1), "-1");
  mintCertificate(tb, b, paramsIdx, stepName(p.step), "1");
  mintCoupon(tb, b, couponName(b.config.amounts[p.step - 1]), "1");

  if (p.kind === "transfer") {
    w0(tb, d, d.core.programmableLogicGlobal, transferAct());
    w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
    w0(tb, d, b.transfer, moveRedeemer());
  } else {
    w0(tb, d, d.core.programmableLogicGlobal, thirdPartyAct());
    // The pair output (the next certificate) is the first output.
    w0(tb, d, d.core.thirdParty, thirdPartyRedeemer(nodeIdx, 0));
    w0(tb, d, b.thirdParty, triggerRedeemer());
  }
  w0(tb, d, b.issuance, mintingActionToData("Advance"));
  w0(
    tb,
    d,
    d.core.issuanceLogic,
    issuanceLogicRedeemer([
      { policy: b.cipPolicy, index: nodeIdx, proof: "ref" },
    ]),
  );

  applyAuthorization(tb, credential, p.authorizer, d.config.networkId);

  p.continuation(b);

  tb.txOut(p.couponAddress, [
    lovelace(MIN_ADA),
    {
      unit: b.cntPolicy + couponName(b.config.amounts[p.step - 1]),
      quantity: "1",
    },
  ]);

  tb.invalidBefore(p.validFromSlot);
  return complete(p, refs);
}

/** Owner-signed coupon claim (§4.5): advance `k-1 -> k` + coupon mint. */
export async function buildClaimOwnerTx(p: ClaimOwnerParams): Promise<string> {
  return buildClaimTx({
    ...p,
    kind: "transfer",
    continuation: (bond) => {
      // Certificate continuation (name advanced, datum preserved).
      p.txBuilder.txOut(p.certificate.output.address, [
        lovelace(MIN_ADA),
        { unit: bond.cipPolicy + stepName(p.step), quantity: "1" },
      ]);
      p.txBuilder.txOutInlineDatumValue(certificateDatumToData(p.datum));
    },
  });
}

/** Issuer-triggered coupon claim (§4.5): third-party spend, coupon to `pay`. */
export async function buildClaimIssuerTx(
  p: ClaimIssuerParams,
): Promise<string> {
  return buildClaimTx({
    ...p,
    couponAddress: p.payoutAddress,
    kind: "thirdParty",
    continuation: (bond) => {
      // Paired continuation: same address and datum; the core third-party
      // rule keeps the spent UTxO's lovelace and unrelated assets, so the
      // value is the input's with only the certificate name swapped.
      p.txBuilder.txOut(
        p.certificate.output.address,
        p.certificate.output.amount
          .filter((a) => a.unit !== bond.cipPolicy + stepName(p.step - 1))
          .concat([{ unit: bond.cipPolicy + stepName(p.step), quantity: "1" }]),
      );
      p.txBuilder.txOutInlineDatumValue(certificateDatumToData(p.datum));
    },
  });
}

// -------------------------------------------------------------- redemption

export interface RedeemParams extends TxBase {
  bond: Bond;
  vault: UTxO;
  coupons: UTxO[];
  payouts: Payout[];
  /**
   * The vault continuation datum. Defaults to the bond's `cntPolicy`; pass the
   * target vault's own datum when it differs (multi-vault deployments).
   */
  vaultDatum?: VaultDatum;
}

/** Burn-to-pay at the vault (§4.6): burn coupons, the vault pays them out. */
export async function buildRedeemTx(p: RedeemParams): Promise<string> {
  const { bond: b } = p;
  const tb = p.txBuilder;

  const burned = couponValue(p.coupons, b.cntPolicy);

  for (const coupon of p.coupons) {
    tb.inputForEvaluation(coupon);
    tb.txIn(
      coupon.input.txHash,
      coupon.input.outputIndex,
      coupon.output.amount,
      coupon.output.address,
    );
  }

  // Burn each coupon name (aggregate per name).
  const byName = new Map<string, bigint>();
  for (const coupon of p.coupons) {
    for (const a of coupon.output.amount) {
      if (a.unit.startsWith(b.cntPolicy) && a.unit.length > 56) {
        const name = a.unit.slice(56);
        byName.set(name, (byName.get(name) ?? 0n) + BigInt(a.quantity));
      }
    }
  }
  for (const [name, qty] of byName) {
    mintCoupon(tb, b, name, "-" + qty.toString());
  }

  vaultSpend(tb, b, p.vault, redeemRedeemer(p.payouts));

  // Payouts first (fresh destinations), then the vault continuation. A payout
  // output still needs min-ADA: the excess over the named amount is covered by
  // the payer's wallet, so the vault's loss stays exactly `burned`.
  for (const payout of p.payouts) {
    const value = payout.amount >= MIN_ADA ? payout.amount : MIN_ADA;
    tb.txOut(payout.address, [lovelace(value)]);
  }
  tb.txOut(p.vault.output.address, addLovelace(p.vault.output.amount, -burned));
  tb.txOutInlineDatumValue(
    vaultDatumToData(p.vaultDatum ?? { cntPolicy: b.cntPolicy }),
  );

  return complete(p);
}

// -------------------------------------------------------------- graduation

export interface GraduateOwnerParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  /** Final step `N` (the burned name). */
  step: number;
  /** Where the principal coupon is delivered. */
  couponAddress: string;
  holderStakeHash: string;
  holderIsScript?: boolean;
  authorizer?: ScriptAuthorizer;
  validFromSlot: number;
}

export interface GraduateIssuerParams extends TxBase {
  bond: Bond;
  node: UTxO;
  certificate: UTxO;
  step: number;
  /** The certificate datum (the shell preserves it byte-for-byte). */
  datum: CertificateDatum;
  payoutAddress: string;
  authorizer?: ScriptAuthorizer;
  validFromSlot: number;
}

/**
 * The shared §4.7 graduation skeleton: burn the final name, mint the
 * principal coupon. The paths differ in who signs and in whether the issuer
 * path emits its paired ghost shell first (core third-party rule).
 */
async function buildGraduateTx(
  p: TxBase & {
    bond: Bond;
    node: UTxO;
    certificate: UTxO;
    step: number;
    couponAddress: string;
    authorizer?: ScriptAuthorizer;
    holderStakeHash?: string;
    holderIsScript?: boolean;
    validFromSlot: number;
    /** `transfer` = owner-signed; `thirdParty` = issuer-triggered. */
    kind: "transfer" | "thirdParty";
    /** The issuer path emits its paired shell before the coupon. */
    shell?: (b: Bond) => void;
  },
): Promise<string> {
  const { deployment: d, bond: b } = p;
  const tb = p.txBuilder;

  const credential =
    p.kind === "transfer"
      ? holderCredential(p.holderStakeHash ?? "", p.holderIsScript)
      : b.config.issuer;
  const spendLogic =
    p.kind === "transfer" ? d.core.transfer : d.core.thirdParty;
  const bondLogic = p.kind === "transfer" ? b.transfer : b.thirdParty;
  const refs = fullReferences([d.refs.protocolParams, p.node], p.authorizer);
  const paramsIdx = referenceIndexOf(refs, d.refs.protocolParams);
  const nodeIdx = referenceIndexOf(refs, p.node);

  const chain = [
    d.core.programmableLogicGlobal,
    spendLogic,
    bondLogic,
    b.issuance,
    d.core.issuanceLogic,
  ];
  const wdrlIdx = wdrlIdxOf(
    d,
    fullWithdrawalKeys(chain, credential, p.authorizer),
  );

  plbSpend(tb, d, p.certificate, paramsIdx, wdrlIdx);

  mintCertificate(tb, b, paramsIdx, stepName(p.step), "-1");
  mintCoupon(tb, b, couponName(b.config.principal), "1");

  if (p.kind === "transfer") {
    w0(tb, d, d.core.programmableLogicGlobal, transferAct());
    w0(tb, d, d.core.transfer, transferRedeemer([{ nodeIdx }]));
    w0(tb, d, b.transfer, moveRedeemer());
  } else {
    w0(tb, d, d.core.programmableLogicGlobal, thirdPartyAct());
    // The pair output (the certificate-less shell) is the first output.
    w0(tb, d, d.core.thirdParty, thirdPartyRedeemer(nodeIdx, 0));
    w0(tb, d, b.thirdParty, triggerRedeemer());
  }
  w0(tb, d, b.issuance, mintingActionToData("Retire"));
  w0(
    tb,
    d,
    d.core.issuanceLogic,
    issuanceLogicRedeemer([
      { policy: b.cipPolicy, index: nodeIdx, proof: "ref" },
    ]),
  );

  applyAuthorization(tb, credential, p.authorizer, d.config.networkId);

  p.shell?.(b);

  tb.txOut(p.couponAddress, [
    lovelace(MIN_ADA),
    { unit: b.cntPolicy + couponName(b.config.principal), quantity: "1" },
  ]);

  tb.invalidBefore(p.validFromSlot);
  return complete(p, refs);
}

/** Owner-signed retirement (§4.7): burn name `N`, mint the principal coupon. */
export async function buildGraduateOwnerTx(
  p: GraduateOwnerParams,
): Promise<string> {
  return buildGraduateTx({ ...p, kind: "transfer" });
}

/** Issuer-triggered retirement (§4.7): third-party burn + principal to `pay`. */
export async function buildGraduateIssuerTx(
  p: GraduateIssuerParams,
): Promise<string> {
  return buildGraduateTx({
    ...p,
    couponAddress: p.payoutAddress,
    kind: "thirdParty",
    shell: (bond) => {
      // Ghost shell: paired continuation keeps address, datum, and — per the
      // core third-party rule — the spent UTxO's lovelace and unrelated
      // assets, with only the certificate removed.
      p.txBuilder.txOut(
        p.certificate.output.address,
        p.certificate.output.amount.filter(
          (a) => a.unit !== bond.cipPolicy + stepName(p.step),
        ),
      );
      p.txBuilder.txOutInlineDatumValue(certificateDatumToData(p.datum));
    },
  });
}

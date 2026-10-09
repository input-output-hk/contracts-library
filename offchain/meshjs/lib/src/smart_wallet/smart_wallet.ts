/**
 * Transaction builders for the smart wallet contract (MeshJS).
 *
 * Action set:
 *   - `buildWalletMintTx`              create the wallet (mint NFT, spend seed UTxO)
 *   - `buildWalletDepositTx`           depositors validate added funds (spenders preserved)
 *   - `buildWalletSpendTx`             pay out (base M-of-N + delegated spenders)
 *   - `buildWalletUpdatePermissionsTx` admin rewrites spenders / depositors
 *   - `buildWalletCloseTx`             burn the NFT and close the wallet
 */

import {
  applyParamsToScript,
  Network,
  resolveScriptHash,
  serializePlutusScript,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import type { Credential } from "../common";
import { smartWalletCode, plutusVersion } from "./blueprint";
import {
  walletBurnRedeemer,
  walletCloseRedeemer,
  walletDepositRedeemer,
  walletMintRedeemer,
  walletSpendRedeemer,
  walletUpdatePermissionsRedeemer,
  walletDatumToData,
  walletParamsToData,
} from "./datum";
import type { DelegatedScript, WalletDatum, WalletParams } from "./types";
import {
  deregisterWithdrawalScript,
  invokeWithdrawalScript,
  registerWithdrawalScript,
} from "./withdrawal_scripts";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

export function smartWalletScript(params: WalletParams): PlutusScript {
  return {
    code: applyParamsToScript(
      smartWalletCode,
      walletParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

export function smartWalletScriptAddress(
  script: PlutusScript,
  networkId = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

function nft(policyId: string, tokenName: string): Asset {
  return { unit: policyId + tokenName, quantity: "1" };
}

/** Merge `extra` into a copy of `base` (by unit) without mutating either input. */
function addAssets(base: Asset[], extra: Asset[]): Asset[] {
  const result = base.map((a) => ({ ...a }));
  for (const a of extra) {
    const existing = result.find((x) => x.unit === a.unit);
    if (existing) {
      existing.quantity = (
        BigInt(existing.quantity) + BigInt(a.quantity)
      ).toString();
    } else {
      result.push({ ...a });
    }
  }
  return result;
}

/**
 * The wallet only knows the scripts listed in its datum maps, so every entry
 * must be covered by a provided script. Fails early with a clear error rather
 * than submitting a transaction the validator will reject.
 */
function assertScriptsCover(
  scripts: PlutusScript[],
  required: DelegatedScript[],
  label: string,
): void {
  const provided = new Set(
    scripts.map((s) => resolveScriptHash(s.code, s.version)),
  );
  for (const { scriptHash } of required) {
    if (!provided.has(scriptHash)) {
      throw new Error(
        `Missing ${label} script for ${scriptHash}: every script in the ` +
          `datum must be provided so it can run or be published.`,
      );
    }
  }
}

// ---------------------------------------------------- Mint

export interface WalletMintParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  walletTokenName: string;
  seedUtxo: UTxO;
  /** Initial datum; every script in its two maps is published in this tx. */
  datum: WalletDatum;
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  admin: Credential;
  authorizer?: ScriptAuthorizer;
  /** Scripts in the initial `spenders` / `depositors` maps (published here). */
  registerScripts?: PlutusScript[];
  network?: Network;
}

export async function buildWalletMintTx(p: WalletMintParams): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const scriptAddr = smartWalletScriptAddress(p.script, networkId);
  const policyId = resolveScriptHash(p.script.code, p.script.version);

  assertScriptsCover(
    p.registerScripts ?? [],
    [...p.datum.spenders, ...p.datum.depositors],
    "registration",
  );

  applyAuthorization(p.txBuilder, p.admin, p.authorizer, networkId);
  for (const script of p.registerScripts ?? []) {
    registerWithdrawalScript(p.txBuilder, script, networkId);
  }

  return await p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", policyId, p.walletTokenName)
    .mintRedeemerValue(walletMintRedeemer(p.outputIndex))
    .mintingScript(p.script.code)
    .txIn(
      p.seedUtxo.input.txHash,
      p.seedUtxo.input.outputIndex,
      p.seedUtxo.output.amount,
      p.seedUtxo.output.address,
    )
    .txOut(scriptAddr, [
      { unit: "lovelace", quantity: DEFAULT_MIN_UTXO_LOVELACE.toString() },
      nft(policyId, p.walletTokenName),
    ])
    .txOutInlineDatumValue(walletDatumToData(p.datum))
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

export interface WalletDepositParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  walletUtxo: UTxO;
  /**
   * Continuation datum: `spenders` must be identical to the wallet UTxO's and
   * `depositors` must keep the same keys (their `data` may advance).
   */
  datum: WalletDatum;
  deposit: Asset[];
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  /** Depositor scripts invoked as withdraw-0 (every `depositors` entry). */
  depositorScripts?: PlutusScript[];
  network?: Network;
}

export async function buildWalletDepositTx(
  p: WalletDepositParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const scriptAddr = smartWalletScriptAddress(p.script, networkId);

  assertScriptsCover(p.depositorScripts ?? [], p.datum.depositors, "depositor");
  for (const script of p.depositorScripts ?? []) {
    invokeWithdrawalScript(p.txBuilder, script, networkId);
  }

  const contValue = addAssets(p.walletUtxo.output.amount, p.deposit);

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.walletUtxo.input.txHash,
      p.walletUtxo.input.outputIndex,
      p.walletUtxo.output.amount,
      p.walletUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(walletDepositRedeemer(p.outputIndex))
    .txInScript(p.script.code)
    .txOut(scriptAddr, contValue)
    .txOutInlineDatumValue(walletDatumToData(p.datum))
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

// ---------------------------------------------------- Spend

export interface WalletSpendParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  walletUtxo: UTxO;
  /** Reference input holding the base M-of-N `WalletConfig`. */
  settingsUtxo: UTxO;
  /**
   * Continuation datum: `depositors` must be identical to the wallet UTxO's,
   * `spenders` must keep the same keys (their `data` may advance).
   */
  datum: WalletDatum;
  /** Payout destination and amount. */
  payoutAddress: string;
  payoutAmount: Asset[];
  /**
   * Wallet continuation (must keep the NFT), at the script address. Its value
   * must be a subset of the wallet UTxO's: a spend only removes value.
   */
  changeAmount: Asset[];
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  /** Member key hashes satisfying the M-of-N floor. */
  signers: string[];
  /** Delegated spender scripts (invoked as withdraw-0 on this spend). */
  spenderScripts?: PlutusScript[];
  /** Validity-range lower bound slot (for stateful scripts that read `now`). */
  invalidBeforeSlot?: number;
  network?: Network;
}

export async function buildWalletSpendTx(
  p: WalletSpendParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const scriptAddr = smartWalletScriptAddress(p.script, networkId);

  assertScriptsCover(p.spenderScripts ?? [], p.datum.spenders, "spender");

  for (const signer of p.signers) {
    p.txBuilder.requiredSignerHash(signer);
  }
  for (const script of p.spenderScripts ?? []) {
    invokeWithdrawalScript(p.txBuilder, script, networkId);
  }
  if (p.invalidBeforeSlot !== undefined) {
    p.txBuilder.invalidBefore(p.invalidBeforeSlot);
  }

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.walletUtxo.input.txHash,
      p.walletUtxo.input.outputIndex,
      p.walletUtxo.output.amount,
      p.walletUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(walletSpendRedeemer())
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    );

  p.txBuilder
    .txOut(p.payoutAddress, p.payoutAmount)
    .txOut(scriptAddr, p.changeAmount)
    .txOutInlineDatumValue(walletDatumToData(p.datum));

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

// ---------------------------------------------------- UpdatePermissions

export interface WalletUpdatePermissionsParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  walletUtxo: UTxO;
  newDatum: WalletDatum;
  outputIndex: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  admin: Credential;
  authorizer?: ScriptAuthorizer;
  /** Scripts added by this update, in either map (published here). */
  registerScripts?: PlutusScript[];
  /** Scripts removed by this update, in either map (unregistered here). */
  deregisterScripts?: PlutusScript[];
  network?: Network;
}

export async function buildWalletUpdatePermissionsTx(
  p: WalletUpdatePermissionsParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const scriptAddr = smartWalletScriptAddress(p.script, networkId);

  applyAuthorization(p.txBuilder, p.admin, p.authorizer, networkId);
  for (const script of p.registerScripts ?? []) {
    registerWithdrawalScript(p.txBuilder, script, networkId);
  }
  for (const script of p.deregisterScripts ?? []) {
    deregisterWithdrawalScript(p.txBuilder, script, networkId);
  }

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.walletUtxo.input.txHash,
      p.walletUtxo.input.outputIndex,
      p.walletUtxo.output.amount,
      p.walletUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(walletUpdatePermissionsRedeemer(p.outputIndex))
    .txInScript(p.script.code)
    .txOut(scriptAddr, p.walletUtxo.output.amount)
    .txOutInlineDatumValue(walletDatumToData(p.newDatum))
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

export interface WalletCloseParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  walletTokenName: string;
  walletUtxo: UTxO;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  admin: Credential;
  authorizer?: ScriptAuthorizer;
  /** Scripts in the wallet's `spenders` and `depositors` maps (unregistered here). */
  deregisterScripts?: PlutusScript[];
  network?: Network;
}

export async function buildWalletCloseTx(
  p: WalletCloseParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const policyId = resolveScriptHash(p.script.code, p.script.version);

  applyAuthorization(p.txBuilder, p.admin, p.authorizer, networkId);
  for (const script of p.deregisterScripts ?? []) {
    deregisterWithdrawalScript(p.txBuilder, script, networkId);
  }

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.walletUtxo.input.txHash,
      p.walletUtxo.input.outputIndex,
      p.walletUtxo.output.amount,
      p.walletUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(walletCloseRedeemer())
    .txInScript(p.script.code)
    .mintPlutusScriptV3()
    .mint("-1", policyId, p.walletTokenName)
    .mintRedeemerValue(walletBurnRedeemer())
    .mintingScript(p.script.code)
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

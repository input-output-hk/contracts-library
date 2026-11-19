/**
 * Datum/redeemer encoding for the smart wallet contract.
 *
 * CBOR constructor layout matching the Aiken blueprint in onchain/plutus.json:
 *   WalletDatum        = Constr 0 [spenders: Pairs<ScriptHash, Data>, depositors: Pairs<ScriptHash, Data>]
 *   WalletConfig       = Constr 0 [members: [VerificationKeyHash], threshold: Int]
 *   SpendingWindowState= Constr 0 [last_upper: Int]
 *   SpendRedeemer      = Spend=0 | UpdatePermissions{out_ix}=1 | Deposit{out_ix}=2 | Close=3
 *   MintRedeemer       = Mint{out_ix}=0 | Burn=1
 *
 * `spenders` / `depositors` are Aiken's `Pairs<k, v>` (`List<Pair<k, v>>`), which
 * serializes as a Plutus association map — encoded here with a JS `Map`.
 */

import {
  type Data,
  mConStr,
  mConStr0,
  mConStr1,
  mConStr2,
} from "@meshsdk/core";

import { addressToData, credentialToData } from "../common";
import { outputRefToData } from "../settings/datum";
import type {
  AssetAllowListParams,
  AssetDenyListParams,
  AssetList,
  DelegatedScript,
  FullRecipientAllowListParams,
  FullRecipientDenyListParams,
  PaymentStakingAllowListParams,
  PaymentStakingDenyListParams,
  SpendingLimitParams,
  SpendingPeriodLimitParams,
  SpendingPeriodState,
  SpendingWindowParams,
  SpendingWindowState,
  WalletConfig,
  WalletDatum,
  WalletParams,
} from "./types";

function pairsToData(scripts: DelegatedScript[]): Map<Data, Data> {
  return new Map(scripts.map((s) => [s.scriptHash, s.data]));
}

export function walletDatumToData(d: WalletDatum): Data {
  return mConStr0([pairsToData(d.spenders), pairsToData(d.depositors)]);
}

export function walletConfigToData(c: WalletConfig): Data {
  return mConStr0([c.members, c.threshold]);
}

export function spendingWindowStateToData(s: SpendingWindowState): Data {
  return mConStr0([s.lastUpper]);
}

export function spendingPeriodStateToData(s: SpendingPeriodState): Data {
  return mConStr0([s.period, s.accSpend]);
}

// ------------------------------------------------------------ redeemers

export function walletSpendRedeemer(): Data {
  return mConStr0([]);
}

export function walletUpdatePermissionsRedeemer(outIx: number): Data {
  return mConStr1([outIx]);
}

export function walletDepositRedeemer(outIx: number): Data {
  return mConStr2([outIx]);
}

export function walletCloseRedeemer(): Data {
  return mConStr(3, []);
}

export function walletMintRedeemer(outIx: number): Data {
  return mConStr0([outIx]);
}

export function walletBurnRedeemer(): Data {
  return mConStr1([]);
}

// ------------------------------------------------------------ validator params

export function walletParamsToData(p: WalletParams): Data[] {
  return [
    outputRefToData(p.seedUtxo),
    p.settingsPolicy,
    p.settingsTokenName,
    p.walletTokenName,
    credentialToData(p.admin),
  ];
}

export function spendingLimitParamsToData(p: SpendingLimitParams): Data[] {
  return [credentialToData(p.wallet), p.walletTokenName, p.bound];
}

export function spendingWindowParamsToData(p: SpendingWindowParams): Data[] {
  return [credentialToData(p.wallet), p.walletTokenName, p.window];
}

export function spendingPeriodLimitParamsToData(
  p: SpendingPeriodLimitParams,
): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    p.interval,
    p.maxSpend,
  ];
}

// ------------------------------------------------- recipient / asset params

export { addressToData };

/** Encode an `AssetList` (`Pairs<PolicyId, List<AssetName>>`) as a Plutus map. */
export function assetListToData(list: AssetList): Data {
  return new Map(list);
}

export function fullRecipientAllowListParamsToData(
  p: FullRecipientAllowListParams,
): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    p.allowed.map(addressToData),
  ];
}

export function fullRecipientDenyListParamsToData(
  p: FullRecipientDenyListParams,
): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    p.denied.map(addressToData),
  ];
}

export function paymentStakingAllowListParamsToData(
  p: PaymentStakingAllowListParams,
): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    p.allowedPayments.map(credentialToData),
    p.allowedStakings.map(credentialToData),
  ];
}

export function paymentStakingDenyListParamsToData(
  p: PaymentStakingDenyListParams,
): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    p.deniedPayments.map(credentialToData),
    p.deniedStakings.map(credentialToData),
  ];
}

export function assetAllowListParamsToData(p: AssetAllowListParams): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    assetListToData(p.allowed),
  ];
}

export function assetDenyListParamsToData(p: AssetDenyListParams): Data[] {
  return [
    credentialToData(p.wallet),
    p.walletTokenName,
    assetListToData(p.denied),
  ];
}

/** Depositor-side asset scripts share the same parameter encoding. */
export const assetDepositAllowListParamsToData = assetAllowListParamsToData;
export const assetDepositDenyListParamsToData = assetDenyListParamsToData;

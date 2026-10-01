/**
 * Datum/redeemer encoding for the smart wallet contract.
 *
 * CBOR constructor layout matching the Aiken blueprint in onchain/plutus.json:
 *   WalletDatum        = Constr 0 [withdrawals: Pairs<ScriptHash, Data>, depositor: Credential]
 *   WalletConfig       = Constr 0 [members: [VerificationKeyHash], threshold: Int]
 *   SpendingWindowState= Constr 0 [last_spend: Int]
 *   SpendRedeemer      = Spend=0 | UpdateConfig{out_ix}=1 | Deposit{out_ix}=2 | Close=3
 *   MintRedeemer       = Mint{out_ix}=0 | Burn=1
 *
 * `withdrawals` is Aiken's `Pairs<k, v>` (`List<Pair<k, v>>`), which serializes
 * as a Plutus association map — encoded here with the `pairs` helper.
 */

import {
  mConStr,
  mConStr0,
  mConStr1,
  mConStr2,
  type Data,
  type TxInput,
} from "@meshsdk/core";

import { credentialToData } from "../common";
import { outputRefToData } from "../settings/datum";
import type {
  SpendingLimitParams,
  SpendingWindowParams,
  SpendingWindowState,
  WalletConfig,
  WalletDatum,
  WalletParams,
} from "./types";

export { credentialToData, outputRefToData };

export function walletDatumToData(d: WalletDatum): Data {
  return mConStr0([
    new Map(d.withdrawals.map((w) => [w.scriptHash, w.data])),
    credentialToData(d.depositor),
  ]);
}

export function walletConfigToData(c: WalletConfig): Data {
  return mConStr0([c.members, c.threshold]);
}

export function spendingWindowStateToData(s: SpendingWindowState): Data {
  return mConStr0([s.lastSpend]);
}

// ------------------------------------------------------------ redeemers

export function walletSpendRedeemer(): Data {
  return mConStr0([]);
}

export function walletUpdateConfigRedeemer(outIx: number): Data {
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
  return [credentialToData(p.wallet), p.bound];
}

export function spendingWindowParamsToData(p: SpendingWindowParams): Data[] {
  return [credentialToData(p.wallet), p.window];
}

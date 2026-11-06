/**
 * Datum/redeemer/parameter encoding for the event-triggered assets (tokenized
 * bond) substandard. Mirrors the Aiken constructor layout in
 * `onchain/lib/event_triggered/types.ak`.
 *
 *   MintingAction     = Constr 0 Register | 1 Deposit | 2 Advance | 3 Retire
 *   TransferAction    = Constr 0 [] (Move)
 *   ThirdPartyAction  = Constr 0 [] (Trigger)
 *   VaultAction       = Constr 0 [] (VaultDeposit) | Constr 1 [payouts] (Redeem)
 *   Credential        = Constr 0 [vkh] (key) | Constr 1 [scripthash] (script)
 *   Option<a>         = Constr 0 [a] (Some) | Constr 1 [] (None)
 *   Inline<a>         = Constr 0 [a]
 *   Address           = Constr 0 [payment, Option<Inline<stake>>]
 *   Payout            = Constr 0 [address, amount]
 *   <record>          = Constr 0 [fields…]  (field order per types.ak)
 */

import {
  type Data,
  deserializeAddress,
  mConStr0,
  mConStr1,
  mConStr2,
  mConStr3,
} from "@meshsdk/core";

import { type Credential, credentialToData } from "../common";
import type {
  CertificateDatum,
  CouponParams,
  MintingAction,
  MintingParams,
  Payout,
  RegistryNode,
  ThirdPartyParams,
  TransferParams,
  VaultDatum,
  VaultNftParams,
  VaultParams,
} from "./types";

// ------------------------------------------------------------- redeemers

export function mintingActionToData(a: MintingAction): Data {
  switch (a) {
    case "Register":
      return mConStr0([]);
    case "Deposit":
      return mConStr1([]);
    case "Advance":
      return mConStr2([]);
    case "Retire":
      return mConStr3([]);
  }
}

export function moveRedeemer(): Data {
  return mConStr0([]);
}

export function triggerRedeemer(): Data {
  return mConStr0([]);
}

export function vaultDepositRedeemer(): Data {
  return mConStr0([]);
}

export function vaultTopUpRedeemer(): Data {
  return mConStr2([]);
}

export function redeemRedeemer(payouts: Payout[]): Data {
  return mConStr1([payouts.map(payoutToData)]);
}

/** The coupon / vault-NFT mint policies take a unit `Data` redeemer. */
export function unitRedeemer(): Data {
  return mConStr0([]);
}

export function payoutToData(p: Payout): Data {
  return mConStr0([addressToData(p.address), p.amount]);
}

/** Encode a bech32 address as Aiken's `Address` (`payment` + `Option<Inline<stake>>`). */
export function addressToData(address: string): Data {
  const a = deserializeAddress(address);
  const payment: Credential =
    a.pubKeyHash !== ""
      ? { kind: "key", hash: a.pubKeyHash }
      : { kind: "script", hash: a.scriptHash };
  const stake: Credential | null =
    a.stakeCredentialHash !== ""
      ? { kind: "key", hash: a.stakeCredentialHash }
      : a.stakeScriptCredentialHash !== ""
        ? { kind: "script", hash: a.stakeScriptCredentialHash }
        : null;
  return mConStr0([
    credentialToData(payment),
    stake === null
      ? mConStr1([])
      : mConStr0([mConStr0([credentialToData(stake)])]),
  ]);
}

// --------------------------------------------------------------- datums

export function certificateDatumToData(d: CertificateDatum): Data {
  return mConStr0([
    d.start,
    d.commit === null ? mConStr1([]) : mConStr0([credentialToData(d.commit)]),
    d.cntPolicy,
  ]);
}

export function vaultDatumToData(d: VaultDatum): Data {
  return mConStr0([d.cntPolicy]);
}

export function registryNodeToData(n: RegistryNode): Data {
  return mConStr0([
    n.key,
    n.next,
    credentialToData(n.mintingLogic),
    credentialToData(n.transferLogic),
    credentialToData(n.thirdPartyLogic),
    credentialToData(n.unfrackingLogic),
    n.globalStateCs,
  ]);
}

// --------------------------------------------------------- asset names

/** The certificate asset name for step `k`: exactly one byte, big-endian. */
export function stepName(k: number): string {
  return k.toString(16).padStart(2, "0");
}

/** Parse a certificate asset name into its step, if it is one byte. */
export function stepOfName(name: string): number | null {
  return name.length === 2 ? Number.parseInt(name, 16) : null;
}

/** The coupon asset name for a lovelace amount: its decimal bytes, hex-encoded. */
export function couponName(amount: number): string {
  return Buffer.from(amount.toString(), "utf8").toString("hex");
}

/** Parse a coupon asset name into its lovelace amount. */
export function decodeCouponName(name: string): number {
  return Number.parseInt(Buffer.from(name, "hex").toString("utf8"), 10);
}

// -------------------------------------------------------------- parameters
// Each validator takes exactly one record parameter; `applyParamsToScript`
// expects an array with one Data per parameter.

export function mintingParamsToData(p: MintingParams): Data[] {
  return [
    mConStr0([
      p.registryNodeCs,
      credentialToData(p.issuer),
      p.transferLogic,
      p.thirdPartyLogic,
      p.vault,
      p.vaultNftCs,
      p.principal,
    ]),
  ];
}

export function transferParamsToData(p: TransferParams): Data[] {
  return [mConStr0([p.registryNodeCs])];
}

export function thirdPartyParamsToData(p: ThirdPartyParams): Data[] {
  return [mConStr0([p.registryNodeCs, credentialToData(p.issuer)])];
}

export function vaultParamsToData(p: VaultParams): Data[] {
  return [mConStr0([p.principal, p.vaultNftCs])];
}

export function vaultNftParamsToData(p: VaultNftParams): Data[] {
  return [mConStr0([credentialToData(p.authority)])];
}

export function couponParamsToData(p: CouponParams): Data[] {
  return [mConStr0([p.cipPolicy, p.principal, p.interval, p.amounts])];
}

/**
 * Datum/redeemer encoding for the settings contract.
 *
 * CBOR constructor layout matching the Aiken blueprint:
 *   SettingsDatum = Constr 0 [current: Data, next: Option<Data>, next_apply: Option<Int>]
 *   Propose       = Constr 0 [out_ix: Int]
 *   Apply         = Constr 1 [out_ix: Int]
 *   Close         = Constr 2 []
 *   Mint          = Constr 0 [out_ix: Int]
 *   Burn          = Constr 1 []
 */

import { mConStr0, mConStr1, mConStr2, type Data } from "@meshsdk/core";

import { credentialToData } from "../common";
import type { OutputRef, SettingsDatum, SettingsParams } from "./types";

export { credentialToData };

function optional<T>(value: T | null, wrap: (v: T) => Data): Data {
  return value === null ? mConStr1([]) : mConStr0([wrap(value)]);
}

export function settingsDatumToData(d: SettingsDatum): Data {
  return mConStr0([
    d.current,
    optional(d.next, (v) => v),
    optional(d.nextApply, (v) => v),
  ]);
}

export function proposeRedeemer(outIx: number): Data {
  return mConStr0([outIx]);
}

export function applyRedeemer(outIx: number): Data {
  return mConStr1([outIx]);
}

export function closeRedeemer(): Data {
  return mConStr2([]);
}

export function mintRedeemer(outIx: number): Data {
  return mConStr0([outIx]);
}

export function burnRedeemer(): Data {
  return mConStr1([]);
}

export function outputRefToData(ref: OutputRef): Data {
  return mConStr0([ref.transactionId, ref.outputIndex]);
}

export function paramsToData(p: SettingsParams): Data[] {
  return [
    outputRefToData(p.seedUtxo),
    credentialToData(p.proposeAuth),
    credentialToData(p.applyAuth),
    p.applyDelay,
  ];
}

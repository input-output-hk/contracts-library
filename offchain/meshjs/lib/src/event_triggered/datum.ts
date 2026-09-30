/**
 * Datum/redeemer/parameter encoding for the event-triggered assets (tokenized
 * bond) substandard. Mirrors the Aiken constructor layout in
 * `onchain/lib/event_triggered/types.ak`.
 *
 *   MintingAction     = Constr 0 [] (RegisterAndMint) | Constr 1 [] (Burn)
 *   TransferAction    = Constr 0 [] (Move)
 *   ThirdPartyAction  = Constr 0 [] (Graduate)
 *   TransformationAction = Constr 0 [] (Update)
 *   Credential        = Constr 0 [vkh] (key) | Constr 1 [scripthash] (script)
 *   Option<a>         = Constr 0 [a] (Some) | Constr 1 [] (None)
 *   ScheduleStep      = Constr 0 [deadline, value]
 *   <record>          = Constr 0 [fields…]  (field order per types.ak)
 */

import { mConStr0, mConStr1, type Data } from "@meshsdk/core";

import { credentialToData } from "../common";
import type {
  BondExtra,
  MintingAction,
  MintingParams,
  NativeMintParams,
  PrincipalDatum,
  ReferenceDatum,
  RegistryNode,
  Schedule,
  ThirdPartyParams,
  TransferParams,
  TransformationParams,
} from "./types";

// ------------------------------------------------------------- redeemers

export function mintingActionToData(a: MintingAction): Data {
  return a === "RegisterAndMint" ? mConStr0([]) : mConStr1([]);
}

export function moveRedeemer(): Data {
  return mConStr0([]);
}

export function graduateRedeemer(): Data {
  return mConStr0([]);
}

export function updateRedeemer(): Data {
  return mConStr0([]);
}

/** The native mint policy's redeemer is `Data` (unit). */
export function nativeMintRedeemer(): Data {
  return mConStr0([]);
}

// --------------------------------------------------------------- datums

function scheduleToData(schedule: Schedule): Data[] {
  return schedule.map((s) => mConStr0([s.deadline, s.value]));
}

export function bondExtraToData(e: BondExtra): Data {
  return mConStr0([scheduleToData(e.schedule), e.value, e.nativePolicy]);
}

export function referenceDatumToData(d: ReferenceDatum): Data {
  return mConStr0([d.metadata, d.version, bondExtraToData(d.extra)]);
}

export function principalDatumToData(d: PrincipalDatum): Data {
  const option = d.paymentCredential === null
    ? mConStr1([])
    : mConStr0([credentialToData(d.paymentCredential)]);
  return mConStr0([option]);
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
      p.transformationScript,
      p.principalName,
      p.referenceName,
      scheduleToData(p.schedule),
      p.scale,
    ]),
  ];
}

export function transferParamsToData(p: TransferParams): Data[] {
  return [mConStr0([p.registryNodeCs, p.finalDeadline])];
}

export function thirdPartyParamsToData(p: ThirdPartyParams): Data[] {
  return [mConStr0([p.registryNodeCs, p.finalDeadline])];
}

export function transformationParamsToData(p: TransformationParams): Data[] {
  return [mConStr0([p.referenceName, scheduleToData(p.schedule)])];
}

export function nativeMintParamsToData(p: NativeMintParams): Data[] {
  return [
    mConStr0([p.cipPolicy, p.principalName, p.scale, scheduleToData(p.schedule)]),
  ];
}
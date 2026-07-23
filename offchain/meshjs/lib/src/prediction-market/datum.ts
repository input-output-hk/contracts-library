/**
 * Datum/redeemer encoding for the prediction-market conditional-token
 * validators.
 *
 * CBOR constructor layout MUST match Aiken's flat-format encoding:
 *
 *   Credential            = Constr 0 [vkh] | Constr 1 [scripthash]
 *   AssetClass            = Constr 0 [policyId, assetName]
 *   TokenInfo             = Constr 0 [AssetClass, amount]
 *   Winner.Yes            = Constr 0 []
 *   Winner.No             = Constr 1 []
 *   Winner.Draw           = Constr 2 []
 *   Option<T>: None       = Constr 0 []
 *   Option<T>: Some(v)    = Constr 1 [v]
 *   OutcomeDatum          = Constr 0 [marketId, cutoff, winner, credential,
 *                                     resolutionTimeout, claimDeadline,
 *                                     collateral]
 *   OutcomeRedeemer       = Constr 0 [Winner]
 *   BeaconMintAction      = Constr 0 [marketId]
 *   RedemptionDatum       = Constr 0 [marketId, beaconPolicy]
 *   RedeemWinner          = Constr 0 [outputIndex]
 *   BurnCompleteSet       = Constr 1 [outputIndex]
 *   ClaimTimeout          = Constr 2 [outputIndex]
 *   ClaimDraw             = Constr 3 [outputIndex]
 *   SweepResidual         = Constr 4 [outputIndex]
 *   MintSet               = Constr 0 [marketId]
 *   BurnSet               = Constr 1 [marketId]
 *   BurnWinner            = Constr 2 [marketId]
 */

import {
  mConStr,
  mConStr0,
  mConStr1,
  mConStr2,
  mConStr3,
  type Data,
} from "@meshsdk/core";
import type {
  AssetClass,
  MintAction,
  Option,
  OutcomeDatum,
  RedemptionDatum,
  RedemptionRedeemer,
  TokenInfo,
  Winner,
} from "./types";

import { credentialToData } from "../common";

export { credentialToData };

export function assetClassToData(a: AssetClass): Data {
  return mConStr0([a.policyId, a.assetName]);
}

export function tokenInfoToData(t: TokenInfo): Data {
  return mConStr0([assetClassToData(t.asset), t.amount]);
}

function winnerToData(w: Winner): Data {
  if (w === "Yes") return mConStr0([]);
  if (w === "No") return mConStr1([]);
  if (w === "Draw") return mConStr2([]);
  return mConStr2([]);
}

function optionToData<T>(o: Option<T>, encode: (v: T) => Data): Data {
  if (o === "None") return mConStr0([]);
  return mConStr1([encode(o.value)]);
}

export function outcomeDatumToData(d: OutcomeDatum): Data {
  return mConStr0([
    d.marketId,
    d.cutoff,
    optionToData(d.winner, winnerToData),
    credentialToData(d.outcomeCredential),
    d.resolutionTimeout,
    d.claimDeadline,
    tokenInfoToData(d.collateral),
  ]);
}

export function resolveRedeemer(winner: Winner): Data {
  return mConStr0([winnerToData(winner)]);
}

export function mintBeaconRedeemer(marketId: string): Data {
  return mConStr0([marketId]);
}

export function redemptionDatumToData(d: RedemptionDatum): Data {
  return mConStr0([d.marketId, d.beaconPolicy]);
}

export function redemptionRedeemerToData(r: RedemptionRedeemer): Data {
  switch (r.variant) {
    case "RedeemWinner":
      return mConStr0([r.outputIndex]);
    case "BurnCompleteSet":
      return mConStr1([r.outputIndex]);
    case "ClaimTimeout":
      return mConStr2([r.outputIndex]);
    case "ClaimDraw":
      return mConStr3([r.outputIndex]);
    case "SweepResidual":
      return mConStr(4, [r.outputIndex]);
  }
}

export function mintActionToData(a: MintAction): Data {
  switch (a.variant) {
    case "MintSet":
      return mConStr0([a.marketId]);
    case "BurnSet":
      return mConStr1([a.marketId]);
    case "BurnWinner":
      return mConStr2([a.marketId]);
  }
}

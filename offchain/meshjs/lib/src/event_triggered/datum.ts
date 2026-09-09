/**
 * Datum/redeemer encoding for the event-triggered assets contract.
 *
 * CBOR constructor layout matching the Aiken blueprint:
 *   Credential        = Constr 0 [vkh]  (key)  |  Constr 1 [scripthash]  (script)
 *   InstrumentState   = Constr 0 [] (Active)  |  Constr 1 [] (Settled)
 *   EventAssetDatum   = Constr 0 [rule, graduation_auth, state]
 *   Spend datum       = Constr 0 [EventAssetDatum] (Some)  |  Constr 1 [] (None)
 *   SpendRedeemer     = Constr 0 [] (ApplyEvent)
 *   MintRedeemer      = Constr 0 [] (Graduate)  |  Constr 1 [] (Retire)
 */

import { mConStr0, mConStr1, type Data } from "@meshsdk/core";

import { credentialToData } from "../common";
import type { EventAssetDatum, InstrumentState } from "./types";

export { credentialToData };

export function instrumentStateToData(s: InstrumentState): Data {
  return s === "Active" ? mConStr0([]) : mConStr1([]);
}

/** The inner `EventAssetDatum` constructor. */
export function eventAssetDatumToData(d: EventAssetDatum): Data {
  return mConStr0([
    credentialToData(d.rule),
    credentialToData(d.graduationAuth),
    instrumentStateToData(d.state),
  ]);
}

/**
 * The spend endpoint's datum, which the on-chain validator types as
 * `Option<EventAssetDatum>`: `Some(d)` for a custodied instrument UTxO,
 * `None` otherwise.
 */
export function instrumentDatumToData(d: EventAssetDatum | null): Data {
  return d === null ? mConStr1([]) : mConStr0([eventAssetDatumToData(d)]);
}

/** The `ApplyEvent` spend redeemer. */
export function applyEventRedeemer(): Data {
  return mConStr0([]);
}

/** The `Graduate` mint redeemer (burn programmable + mint graduated native). */
export function graduateRedeemer(): Data {
  return mConStr0([]);
}

/** The `Retire` mint redeemer (burn-only retirement). */
export function retireRedeemer(): Data {
  return mConStr1([]);
}

/**
 * Datum/redeemer encoding for the `counter_*` demo validators.
 *
 * CBOR constructor layout matching the Aiken blueprint:
 *   CounterDatum    = Constr 0 [count: Int, owner: Credential,
 *                              prev_input: Option<OutputReference>]
 *   SteppedCounter  = Constr 0 [...CounterDatum]          (Unstepped)
 *                   | Constr 1 [count, owner, prev_input, step: Int]
 *   CounterRedeemer = Tick=0 | Upgrade=1
 */

import {
  type Data,
  deserializeDatum,
  mConStr0,
  mConStr1,
  type UTxO,
} from "@meshsdk/core";

import { type Credential, credentialToData } from "../../common";
import { asBytes, asConstr, asInt } from "../../upgradeability/datum";
import type { CounterDatum, OutputRef, SteppedCounterDatum } from "./types";

export { credentialToData };

// ------------------------------------------------------------------ encoding

/** Encode a UTxO reference as the Aiken `OutputReference` record. */
export function outputRefToData(r: OutputRef): Data {
  return mConStr0([r.txHash, r.outputIndex]);
}

/** Encode `prevInput` as the Aiken `Option<OutputReference>` field. */
function prevInputToData(prevInput: OutputRef | null): Data {
  return prevInput === null
    ? mConStr1([])
    : mConStr0([outputRefToData(prevInput)]);
}

export function counterDatumToData(d: CounterDatum): Data {
  return mConStr0([
    d.count,
    credentialToData(d.owner),
    prevInputToData(d.prevInput),
  ]);
}

/** The ordinary counter step, accepted by the forced logic and both versions. */
/** Encode the `Stepped` shape that `counter_logic_stepped` writes. */
export function steppedCounterDatumToData(d: SteppedCounterDatum): Data {
  return mConStr1([
    d.count,
    credentialToData(d.owner),
    prevInputToData(d.prevInput),
    d.step,
  ]);
}

export function tickRedeemer(): Data {
  return mConStr0([]);
}

/** The dedicated migration path, accepted only by the opt-in V1 validator. */
export function upgradeRedeemer(): Data {
  return mConStr1([]);
}

// ------------------------------------------------------------------ decoding

function credentialFromJson(data: unknown, what: string): Credential {
  const c = asConstr(data, what);
  if (c.constructor !== 0 && c.constructor !== 1) {
    throw new Error(`Malformed datum: unknown credential kind for ${what}.`);
  }
  const hash = asBytes(c.fields[0], what);
  return c.constructor === 0 ? { kind: "key", hash } : { kind: "script", hash };
}

function outputRefFromJson(data: unknown, what: string): OutputRef {
  const r = asConstr(data, what);
  if (r.constructor !== 0 || r.fields.length !== 2) {
    throw new Error(`Malformed datum: malformed output reference for ${what}.`);
  }
  return {
    txHash: asBytes(r.fields[0], what),
    outputIndex: asInt(r.fields[1], what),
  };
}

/** Decode the Aiken `Option<OutputReference>` continuation tag. */
function optionalOutputRefFromJson(
  data: unknown,
  what: string,
): OutputRef | null {
  const o = asConstr(data, what);
  if (o.constructor === 1) {
    return null;
  }
  if (o.constructor !== 0 || o.fields.length !== 1) {
    throw new Error(`Malformed datum: malformed option for ${what}.`);
  }
  return outputRefFromJson(o.fields[0], what);
}

/** Decode the counter state from a UTxO's inline datum. Throws on absence/malformation. */
export function counterDatumFromUtxo(utxo: UTxO): CounterDatum {
  if (!utxo.output.plutusData) {
    throw new Error(
      `The counter UTxO (${utxo.input.txHash}#${utxo.input.outputIndex}) has no ` +
        "inline datum; the builders need `count`, `owner` and `prevInput` from it.",
    );
  }
  const d = asConstr(
    deserializeDatum(utxo.output.plutusData),
    "the counter datum",
  );
  if (d.constructor !== 0 || d.fields.length !== 3) {
    throw new Error(
      "Malformed counter datum: expected Constr 0 [count, owner, prevInput].",
    );
  }
  return {
    count: asInt(d.fields[0], "count"),
    owner: credentialFromJson(d.fields[1], "owner"),
    prevInput: optionalOutputRefFromJson(d.fields[2], "prevInput"),
  };
}

/**
 * Decode either counter shape: the original datum (step 1, as the stepped
 * logic reads it) or `Stepped`. Throws on absence/malformation.
 */
export function steppedCounterFromUtxo(utxo: UTxO): SteppedCounterDatum {
  if (!utxo.output.plutusData) {
    throw new Error(
      `The counter UTxO (${utxo.input.txHash}#${utxo.input.outputIndex}) has no inline datum.`,
    );
  }
  const d = asConstr(
    deserializeDatum(utxo.output.plutusData),
    "the counter datum",
  );
  const original = d.constructor === 0 && d.fields.length === 3;
  const stepped = d.constructor === 1 && d.fields.length === 4;
  if (!original && !stepped) {
    throw new Error(
      "Malformed counter datum: expected Constr 0 [count, owner, prevInput] " +
        "or Constr 1 [count, owner, prevInput, step].",
    );
  }
  return {
    count: asInt(d.fields[0], "count"),
    owner: credentialFromJson(d.fields[1], "owner"),
    prevInput: optionalOutputRefFromJson(d.fields[2], "prevInput"),
    step: stepped ? asInt(d.fields[3], "step") : 1,
  };
}

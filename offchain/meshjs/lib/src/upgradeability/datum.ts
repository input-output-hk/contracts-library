/**
 * Datum/redeemer encoding for the upgradeability counter validators.
 *
 * CBOR constructor layout matching the Aiken blueprint:
 *   CounterDatum    = Constr 0 [count: Int, owner: Credential]
 *   CounterRedeemer = Tick=0 | Upgrade=1
 *   Registry        = Map<bytes, bytes>   (the settings datum's `current`)
 *
 * The forwarder's spend redeemer and the logic/migration withdrawal redeemers
 * are opaque `Data` on-chain, so any well-formed value works — the unit.
 */

import {
  deserializeDatum,
  mConStr0,
  mConStr1,
  type Data,
  type UTxO,
} from "@meshsdk/core";

import { credentialToData, type Credential } from "../common";
import type { CounterDatum, Registry } from "./types";

export { credentialToData };

// ------------------------------------------------------------------ encoding

export function counterDatumToData(d: CounterDatum): Data {
  return mConStr0([d.count, credentialToData(d.owner)]);
}

/** The ordinary counter step, accepted by the forced logic and both versions. */
export function tickRedeemer(): Data {
  return mConStr0([]);
}

/** The dedicated migration path, accepted only by the opt-in V1 validator. */
export function upgradeRedeemer(): Data {
  return mConStr1([]);
}

/**
 * Redeemer for the opaque `Data` paths: the forwarder's spend and the
 * logic/migration withdraw-0 executions. The on-chain validators never inspect
 * it, so the unit is always admissible.
 */
export function opaqueRedeemer(): Data {
  return mConStr0([]);
}

/**
 * Encode a registry as the settings datum's `current` value: a Plutus map of
 * byte arrays to byte arrays (hex script hashes).
 */
export function registryToData(entries: Registry): Data {
  const map = new Map<Data, Data>();
  for (const [key, value] of entries) {
    map.set(key, value);
  }
  return map;
}

// ------------------------------------------------------------------ decoding

type DatumJson =
  | { constructor: number; fields: unknown[] }
  | { map: { k: unknown; v: unknown }[] }
  | { list: unknown[] }
  | { int: number | bigint | string }
  | { bytes: string };

function asConstr(
  data: unknown,
  what: string,
): { constructor: number; fields: unknown[] } {
  const d = data as { constructor?: unknown; fields?: unknown };
  if (
    (typeof d.constructor !== "number" && typeof d.constructor !== "bigint") ||
    !Array.isArray(d.fields)
  ) {
    throw new Error(`Malformed datum: expected a constructor for ${what}.`);
  }
  return { constructor: Number(d.constructor), fields: d.fields };
}

function asBytes(data: unknown, what: string): string {
  const d = data as DatumJson;
  if (!("bytes" in d) || typeof d.bytes !== "string") {
    throw new Error(`Malformed datum: expected bytes for ${what}.`);
  }
  return d.bytes;
}

function asInt(data: unknown, what: string): number {
  const d = data as DatumJson;
  if (!("int" in d)) {
    throw new Error(`Malformed datum: expected an integer for ${what}.`);
  }
  return Number(d.int);
}

function credentialFromJson(data: unknown, what: string): Credential {
  const c = asConstr(data, what);
  if (c.constructor !== 0 && c.constructor !== 1) {
    throw new Error(`Malformed datum: unknown credential kind for ${what}.`);
  }
  const hash = asBytes(c.fields[0], what);
  return c.constructor === 0 ? { kind: "key", hash } : { kind: "script", hash };
}

/** Decode the counter state from a UTxO's inline datum. Throws on absence/malformation. */
export function counterDatumFromUtxo(utxo: UTxO): CounterDatum {
  if (!utxo.output.plutusData) {
    throw new Error(
      `The counter UTxO (${utxo.input.txHash}#${utxo.input.outputIndex}) has no ` +
        "inline datum; the builders need `count` and `owner` from it.",
    );
  }
  const d = asConstr(
    deserializeDatum(utxo.output.plutusData),
    "the counter datum",
  );
  if (d.constructor !== 0 || d.fields.length !== 2) {
    throw new Error(
      "Malformed counter datum: expected Constr 0 [count, owner].",
    );
  }
  return {
    count: asInt(d.fields[0], "count"),
    owner: credentialFromJson(d.fields[1], "owner"),
  };
}

/**
 * Read the registry from the settings UTxO's inline datum (`current` value).
 * Throws if the UTxO carries no inline datum or the value is not a map of
 * byte arrays — mirroring the on-chain `decode_registry` rejection.
 */
export function registryFromUtxo(settingsUtxo: UTxO): Registry {
  if (!settingsUtxo.output.plutusData) {
    throw new Error(
      `The settings UTxO (${settingsUtxo.input.txHash}#${settingsUtxo.input.outputIndex}) ` +
        "has no inline datum.",
    );
  }
  const d = asConstr(
    deserializeDatum(settingsUtxo.output.plutusData),
    "the settings datum",
  );
  if (d.constructor !== 0 || d.fields.length !== 3) {
    throw new Error(
      "Malformed settings datum: expected Constr 0 [current, next, next_apply].",
    );
  }
  const current = d.fields[0] as DatumJson;
  if (!("map" in current) || !Array.isArray(current.map)) {
    throw new Error(
      "Malformed registry: the settings `current` value is not a map.",
    );
  }
  const registry: Registry = new Map();
  for (const entry of current.map) {
    registry.set(
      asBytes(entry.k, "registry key"),
      asBytes(entry.v, "registry value"),
    );
  }
  return registry;
}

/**
 * Registry encoding, and the redeemer for the opaque paths.
 *
 *   Registry = Map<bytes, bytes>   (the settings datum's `current`; keys
 *                                   strictly ascending, values 28-byte
 *                                   script hashes)
 *
 * The forwarder's redeemer and a delegate's withdraw-0 redeemer are opaque
 * `Data` on-chain, so any well-formed value works: the unit.
 */

import {
  deserializeDatum,
  mConStr0,
  type Data,
  type UTxO,
} from "@meshsdk/core";

import type { Registry } from "./types";

/**
 * Redeemer for the opaque `Data` paths: a forwarder's spend or mint and a
 * delegate's withdraw-0. The on-chain predicates never inspect it, so the unit
 * is always admissible.
 */
export function opaqueRedeemer(): Data {
  return mConStr0([]);
}

/**
 * Encode a registry as the settings datum's `current` value: a Plutus map of
 * byte arrays to byte arrays (hex script hashes), sorted by key. The on-chain
 * `decode_registry` rejects a map whose keys are not strictly ascending.
 */
export function registryToData(entries: Registry): Data {
  const map = new Map<Data, Data>();
  const sorted = [...entries].sort(([a], [b]) => compareHex(a, b));
  for (const [key, value] of sorted) {
    map.set(key, value);
  }
  return map;
}

/**
 * Byte-wise order of two hex strings. For lowercase hex, string order is byte
 * order (a shorter prefix sorts first, as on-chain).
 */
function compareHex(a: string, b: string): number {
  const x = a.toLowerCase();
  const y = b.toLowerCase();
  return x < y ? -1 : x > y ? 1 : 0;
}

// ------------------------------------------------------------------ decoding

/** A deserialized datum in Mesh's JSON form. */
export type DatumJson =
  | { constructor: number; fields: unknown[] }
  | { map: { k: unknown; v: unknown }[] }
  | { list: unknown[] }
  | { int: number | bigint | string }
  | { bytes: string };

export function asConstr(
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

export function asBytes(data: unknown, what: string): string {
  const d = data as DatumJson;
  if (!("bytes" in d) || typeof d.bytes !== "string") {
    throw new Error(`Malformed datum: expected bytes for ${what}.`);
  }
  return d.bytes;
}

export function asInt(data: unknown, what: string): number {
  const d = data as DatumJson;
  if (!("int" in d)) {
    throw new Error(`Malformed datum: expected an integer for ${what}.`);
  }
  return Number(d.int);
}

/**
 * Read the registry from the settings UTxO's inline datum (`current` value).
 * Throws if the UTxO carries no inline datum, the value is not a map of byte
 * arrays, its keys are not strictly ascending, or a value is not a 28-byte
 * hash, mirroring the on-chain `decode_registry` rejection.
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
  let previous: string | undefined;
  for (const entry of current.map) {
    const key = asBytes(entry.k, "registry key");
    const value = asBytes(entry.v, "registry value");
    if (previous !== undefined && compareHex(previous, key) >= 0) {
      throw new Error(
        "Malformed registry: keys are not in strictly ascending order.",
      );
    }
    if (value.length !== 56) {
      throw new Error(
        `Malformed registry: the value for ${key} is not a 28-byte script hash.`,
      );
    }
    registry.set(key, value);
    previous = key;
  }
  return registry;
}

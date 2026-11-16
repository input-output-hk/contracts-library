import {
  applyCborEncoding,
  deserializeDatum,
  type MeshTxBuilder,
  mConStr0,
  mConStr1,
  serializeData,
  type UTxO,
} from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import {
  opaqueRedeemer,
  registryFromUtxo,
  registryToData,
} from "../src/upgradeability/datum";
import type { Registry } from "../src/upgradeability/types";
import {
  addDelegateInvocation,
  readRegistry,
} from "../src/upgradeability/upgradeability";
import { compiledCode, validatorHash } from "../src/vesting/blueprint";

/** A MeshTxBuilder stand-in that records the methods called on it. */
function recorder() {
  const calls: { method: string; args: unknown[] }[] = [];
  const proxy: unknown = new Proxy(
    {},
    {
      get(_t, prop) {
        if (prop === "then" || prop === "catch" || prop === "finally") {
          return undefined;
        }
        return (...args: unknown[]) => {
          calls.push({ method: String(prop), args });
          return proxy;
        };
      },
    },
  );
  return { txBuilder: proxy as MeshTxBuilder, calls };
}

// ------------------------------------------------------------------- fixtures

/** Any script stands in for a delegate; the vesting blueprint is handy. */
const DELEGATE_CBOR = applyCborEncoding(compiledCode);
const DELEGATE_HASH = validatorHash;
const OWN_HASH = "aa".repeat(28);

/** A settings UTxO whose `current` value is the given registry. */
function settingsUtxo(registry: Registry): UTxO {
  return {
    input: { txHash: "dd".repeat(32), outputIndex: 9 },
    output: {
      address: "addr_test_settings",
      amount: [{ unit: "lovelace", quantity: "2000000" }],
      plutusData: serializeData(
        mConStr0([registryToData(registry), mConStr1([]), mConStr1([])]),
      ),
    },
  };
}

/**
 * A settings UTxO whose `current` value is a raw map in the given entry order,
 * duplicates included. `registryToData` sorts and a JS `Map` drops duplicate
 * keys, so malformed registries are written in Mesh's JSON datum form instead.
 */
function rawRegistryUtxo(entries: [string, string][]): UTxO {
  const datum = {
    constructor: 0,
    fields: [
      { map: entries.map(([k, v]) => ({ k: { bytes: k }, v: { bytes: v } })) },
      { constructor: 1, fields: [] },
      { constructor: 1, fields: [] },
    ],
  };
  return {
    input: { txHash: "ee".repeat(32), outputIndex: 0 },
    output: {
      address: "addr_test_settings",
      amount: [],
      plutusData: serializeData(datum, "JSON"),
    },
  };
}

// ------------------------------------------------------------------ registry

describe("registry encoding", () => {
  it("encodes as a Plutus map of byte arrays and round-trips", () => {
    const registry: Registry = new Map([
      ["aa".repeat(28), "bb".repeat(28)],
      ["cc".repeat(28), "dd".repeat(28)],
    ]);
    const json = deserializeDatum(serializeData(registryToData(registry)));
    expect(Object.keys(json)).toEqual(["map"]);
    expect(json.map).toHaveLength(2);
    expect(json.map[0].k.bytes).toMatch(/^[0-9a-f]{56}$/);
    expect(readRegistry(settingsUtxo(registry))).toEqual(registry);
  });

  it("encodes with its keys sorted", () => {
    const registry: Registry = new Map([
      ["cc".repeat(28), "dd".repeat(28)],
      ["aa".repeat(28), "bb".repeat(28)],
    ]);
    const json = deserializeDatum(serializeData(registryToData(registry)));
    expect(json.map.map((e: { k: { bytes: string } }) => e.k.bytes)).toEqual([
      "aa".repeat(28),
      "cc".repeat(28),
    ]);
  });

  it("rejects keys that are not strictly ascending", () => {
    const unsorted = rawRegistryUtxo([
      ["cc".repeat(28), "dd".repeat(28)],
      ["aa".repeat(28), "bb".repeat(28)],
    ]);
    expect(() => registryFromUtxo(unsorted)).toThrow(/ascending/i);
    const duplicated = rawRegistryUtxo([
      ["aa".repeat(28), "bb".repeat(28)],
      ["aa".repeat(28), "dd".repeat(28)],
    ]);
    expect(() => registryFromUtxo(duplicated)).toThrow(/ascending/i);
  });

  it("rejects a value that is not a 28-byte hash", () => {
    const short = rawRegistryUtxo([["aa".repeat(28), "bb"]]);
    expect(() => registryFromUtxo(short)).toThrow(/28-byte/i);
  });

  it("rejects a settings UTxO whose current value is not a map", () => {
    const bad: UTxO = {
      input: { txHash: "dd".repeat(32), outputIndex: 9 },
      output: {
        address: "addr_test_settings",
        amount: [],
        plutusData: serializeData(mConStr0([5, mConStr1([]), mConStr1([])])),
      },
    };
    expect(() => registryFromUtxo(bad)).toThrow(/not a map/i);
  });

  it("the opaque redeemer is the unit", () => {
    const json = deserializeDatum(serializeData(opaqueRedeemer()));
    expect(json.constructor).toBe(0n);
    expect(json.fields).toHaveLength(0);
  });
});

// ------------------------------------------------------- delegate invocation

describe("addDelegateInvocation", () => {
  const params = (
    registry: Registry,
    overrides: Partial<Parameters<typeof addDelegateInvocation>[0]> = {},
  ): Parameters<typeof addDelegateInvocation>[0] => ({
    txBuilder: recorder().txBuilder,
    ownHash: OWN_HASH,
    delegateAuthorizer: { scriptCbor: DELEGATE_CBOR },
    settingsUtxo: settingsUtxo(registry),
    ...overrides,
  });

  it("throws when the own hash is not registered", () => {
    expect(() => addDelegateInvocation(params(new Map()))).toThrow(
      /not registered/i,
    );
  });

  it("throws when the authorizer is not the registered delegate", () => {
    const registry: Registry = new Map([[OWN_HASH, "ee".repeat(28)]]);
    expect(() => addDelegateInvocation(params(registry))).toThrow(
      /does not match the credential/i,
    );
  });

  it("refuses a manual authorizer, which cannot be checked", () => {
    const registry: Registry = new Map([[OWN_HASH, DELEGATE_HASH]]);
    expect(() =>
      addDelegateInvocation(
        params(registry, { delegateAuthorizer: { manual: true } }),
      ),
    ).toThrow(/manual/);
  });

  it("wires the delegate's withdraw-0 and the settings reference input", () => {
    const registry: Registry = new Map([[OWN_HASH, DELEGATE_HASH]]);
    const { txBuilder, calls } = recorder();
    const delegate = addDelegateInvocation(params(registry, { txBuilder }));

    expect(delegate).toBe(DELEGATE_HASH);
    const methods = calls.map((c) => c.method);
    expect(methods).toContain("withdrawalPlutusScriptV3");
    expect(methods).toContain("withdrawalScript");
    const ref = calls.find((c) => c.method === "readOnlyTxInReference");
    expect(ref?.args).toEqual(["dd".repeat(32), 9]);
  });
});

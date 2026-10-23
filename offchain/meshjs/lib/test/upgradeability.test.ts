import {
  applyCborEncoding,
  deserializeAddress,
  deserializeDatum,
  mConStr0,
  mConStr1,
  resolveScriptHash,
  serializeData,
  type MeshTxBuilder,
  type UTxO,
} from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import {
  forwarderCompiledCode,
  forwarderValidatorHash,
  logicCompiledCode,
  logicValidatorHash,
  migrationCompiledCode,
  migrationValidatorHash,
  v1CompiledCode,
  v1ValidatorHash,
  v2CompiledCode,
  v2ValidatorHash,
} from "../src/upgradeability/blueprint";
import {
  counterDatumFromUtxo,
  counterDatumToData,
  registryFromUtxo,
  registryToData,
  tickRedeemer,
  upgradeRedeemer,
} from "../src/upgradeability/datum";
import {
  addressToData,
  buildForwardTx,
  buildUpgradeTx,
  counterForwarderScript,
  counterLogicScript,
  counterMigrationScript,
  counterScriptAddress,
  counterScriptHash,
  counterV1Script,
  counterV2Script,
  readRegistry,
} from "../src/upgradeability/upgradeability";
import type {
  CounterDatum,
  Credential,
  Registry,
  SettingsRefParams,
} from "../src/upgradeability/types";

/** A MeshTxBuilder stand-in that records the methods called on it. */
function recorder() {
  const calls: { method: string; args: unknown[] }[] = [];
  const proxy: unknown = new Proxy(
    {},
    {
      get(_t, prop) {
        // `await proxy` would treat the recorder as a pending thenable and hang.
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

const SETTINGS_POLICY = "aa".repeat(28);
const SETTINGS_NAME = "73657474696e6773"; // "settings"

const PARAMS: SettingsRefParams = {
  settingsPolicy: SETTINGS_POLICY,
  settingsTokenName: SETTINGS_NAME,
};

const OWNER: Credential = { kind: "key", hash: "11".repeat(28) };
const SCRIPT_OWNER: Credential = { kind: "script", hash: "22".repeat(28) };

/** Two distinct, valid bech32 script addresses to use as migration targets. */
const V2_ADDR = counterScriptAddress(counterV2Script(), 0);
const V2_ADDR_ALT = counterScriptAddress(counterLogicScript(PARAMS), 0);

const collat: UTxO = {
  input: { txHash: "cc".repeat(32), outputIndex: 0 },
  output: {
    address: "addr_test_collateral",
    amount: [{ unit: "lovelace", quantity: "5000000" }],
  },
};

/** A UTxO reference for `prevInput` fixtures. */
const PREV_REF = { txHash: "aa".repeat(32), outputIndex: 3 };

function counterUtxo(d: CounterDatum, index = 0): UTxO {
  return {
    input: { txHash: "bb".repeat(32), outputIndex: index },
    output: {
      address: "addr_test_counter",
      amount: [{ unit: "lovelace", quantity: "2000000" }],
      plutusData: serializeData(counterDatumToData(d)),
    },
  };
}

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

function forwardTxParams(
  registry: Registry,
  overrides: Partial<Parameters<typeof buildForwardTx>[0]> = {},
): Parameters<typeof buildForwardTx>[0] {
  const forwarderScript = counterForwarderScript(PARAMS);
  return {
    txBuilder: recorder().txBuilder,
    forwarderScript,
    logicAuthorizer: { scriptCbor: counterLogicScript(PARAMS).code },
    forwarderUtxo: counterUtxo({ count: 3, owner: OWNER, prevInput: null }),
    settingsUtxo: settingsUtxo(registry),
    utxos: [],
    changeAddress: "addr_test_change",
    collateralUtxo: collat,
    ...overrides,
  };
}

function upgradeTxParams(
  registry: Registry,
  overrides: Partial<Parameters<typeof buildUpgradeTx>[0]> = {},
): Parameters<typeof buildUpgradeTx>[0] {
  const v1Script = counterV1Script(PARAMS);
  return {
    txBuilder: recorder().txBuilder,
    v1Script,
    migrationAuthorizer: {
      scriptCbor: counterMigrationScript({
        ...PARAMS,
        v2Address: V2_ADDR,
      }).code,
    },
    v1Utxo: counterUtxo({ count: 5, owner: OWNER, prevInput: PREV_REF }, 1),
    settingsUtxo: settingsUtxo(registry),
    v2Address: V2_ADDR,
    utxos: [],
    changeAddress: "addr_test_change",
    collateralUtxo: collat,
    ...overrides,
  };
}

// ------------------------------------------------------------- blueprint pins

describe("blueprint pins", () => {
  it("each pinned hash matches its compiled code", () => {
    const pins: [string, string, string][] = [
      ["forwarder", forwarderCompiledCode, forwarderValidatorHash],
      ["logic", logicCompiledCode, logicValidatorHash],
      ["v1", v1CompiledCode, v1ValidatorHash],
      ["migration", migrationCompiledCode, migrationValidatorHash],
      ["v2", v2CompiledCode, v2ValidatorHash],
    ];
    for (const [name, code, hash] of pins) {
      expect(hash, name).toMatch(/^[0-9a-f]{56}$/);
      expect(resolveScriptHash(applyCborEncoding(code), "V3"), name).toBe(hash);
    }
  });
});

// ------------------------------------------------------------ script factories

describe("counter script factories", () => {
  it("the unparameterized v2 script hashes to its pinned blueprint hash", () => {
    expect(counterScriptHash(counterV2Script())).toBe(v2ValidatorHash);
  });

  it("parameterized scripts hash to 56-hex and differ from the raw blueprint", () => {
    for (const script of [
      counterForwarderScript(PARAMS),
      counterLogicScript(PARAMS),
      counterV1Script(PARAMS),
    ]) {
      expect(counterScriptHash(script)).toMatch(/^[0-9a-f]{56}$/);
    }
    expect(counterScriptHash(counterLogicScript(PARAMS))).not.toBe(
      logicValidatorHash,
    );
  });

  it("the migration script hash depends on the v2 target address", () => {
    const a = counterMigrationScript({ ...PARAMS, v2Address: V2_ADDR_ALT });
    const b = counterMigrationScript({ ...PARAMS, v2Address: V2_ADDR });
    expect(counterScriptHash(a)).not.toBe(counterScriptHash(b));
  });

  it("addressToData encodes the Aiken Address record (payment + stake option)", () => {
    const script = counterV2Script();
    const addr = counterScriptAddress(script, 0);
    const json = deserializeDatum(serializeData(addressToData(addr)));
    // Constr 0 [payment: Script(hash), stake: None]
    expect(json.constructor).toBe(0n);
    const payment = json.fields[0];
    expect(payment.constructor).toBe(1n); // Script credential
    expect(payment.fields[0].bytes).toBe(counterScriptHash(script));
    const stake = json.fields[1];
    expect(stake.constructor).toBe(1n); // None
    expect(stake.fields).toHaveLength(0);
    expect(deserializeAddress(addr).scriptHash).toBe(counterScriptHash(script));
  });
});

// ------------------------------------------------------------- datum encoding

describe("datum/redeemer encoding", () => {
  it("counter datum round-trips through CBOR", () => {
    const d: CounterDatum = { count: 7, owner: OWNER, prevInput: PREV_REF };
    expect(counterDatumFromUtxo(counterUtxo(d))).toEqual(d);
  });

  it("counter datum round-trips a null prevInput (genesis lock)", () => {
    const d: CounterDatum = { count: 0, owner: OWNER, prevInput: null };
    expect(counterDatumFromUtxo(counterUtxo(d))).toEqual(d);
  });

  it("encodes prevInput as Some(OutputReference)", () => {
    const json = deserializeDatum(
      serializeData(
        counterDatumToData({ count: 1, owner: OWNER, prevInput: PREV_REF }),
      ),
    );
    expect(json.fields).toHaveLength(3);
    const some = json.fields[2];
    expect(some.constructor).toBe(0n); // Some
    const ref = some.fields[0];
    expect(ref.constructor).toBe(0n); // OutputReference record
    expect(ref.fields[0].bytes).toBe(PREV_REF.txHash);
    expect(Number(ref.fields[1].int)).toBe(PREV_REF.outputIndex);
  });

  it("tick is constructor 0 and upgrade is constructor 1", () => {
    const tick = deserializeDatum(serializeData(tickRedeemer()));
    expect(tick.constructor).toBe(0n);
    expect(tick.fields).toHaveLength(0);
    const upgrade = deserializeDatum(serializeData(upgradeRedeemer()));
    expect(upgrade.constructor).toBe(1n);
    expect(upgrade.fields).toHaveLength(0);
  });

  it("the registry encodes as a Plutus map of byte arrays and round-trips", () => {
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

  it("rejects UTxOs without an inline datum or with a wrong datum shape", () => {
    const bare: UTxO = {
      input: { txHash: "bb".repeat(32), outputIndex: 0 },
      output: { address: "addr_test_counter", amount: [] },
    };
    expect(() => counterDatumFromUtxo(bare)).toThrow(/no inline datum/i);

    const wrong: UTxO = {
      ...bare,
      output: {
        ...bare.output,
        plutusData: serializeData(mConStr0([1, 2])),
      },
    };
    expect(() => counterDatumFromUtxo(wrong)).toThrow(/Constr 0/);
  });
});

// ------------------------------------------------------------- builder guards

describe("buildForwardTx guards", () => {
  it("throws when the forwarder is not registered in the registry", async () => {
    await expect(buildForwardTx(forwardTxParams(new Map()))).rejects.toThrow(
      /not registered/i,
    );
  });

  it("throws when the logic script does not match the registry entry", async () => {
    const registered: Registry = new Map([
      [counterScriptHash(counterForwarderScript(PARAMS)), "ee".repeat(28)],
    ]);
    await expect(
      buildForwardTx(
        forwardTxParams(registered, {
          logicAuthorizer: { scriptCbor: counterV2Script().code },
        }),
      ),
    ).rejects.toThrow(/does not match the credential/i);
  });

  it("wires the settings reference input and the logic withdraw-0", async () => {
    const registered: Registry = new Map([
      [
        counterScriptHash(counterForwarderScript(PARAMS)),
        counterScriptHash(counterLogicScript(PARAMS)),
      ],
    ]);
    const { txBuilder, calls } = recorder();
    await buildForwardTx(forwardTxParams(registered, { txBuilder }));

    const methods = calls.map((c) => c.method);
    expect(methods).toContain("spendingPlutusScriptV3");
    expect(methods).toContain("txInInlineDatumPresent");
    expect(methods).toContain("readOnlyTxInReference");
    expect(methods).toContain("withdrawalPlutusScriptV3");
    expect(methods).toContain("withdrawalScript");

    const ref = calls.find((c) => c.method === "readOnlyTxInReference");
    expect(ref?.args[0]).toBe("dd".repeat(32));
    expect(ref?.args[1]).toBe(9);
  });

  it("tags the continuation with the spent UTxO as prevInput", async () => {
    const registered: Registry = new Map([
      [
        counterScriptHash(counterForwarderScript(PARAMS)),
        counterScriptHash(counterLogicScript(PARAMS)),
      ],
    ]);
    const { txBuilder, calls } = recorder();
    await buildForwardTx(forwardTxParams(registered, { txBuilder }));

    const out = calls.find((c) => c.method === "txOutInlineDatumValue");
    const json = deserializeDatum(serializeData(out?.args[0]));
    expect(Number(json.fields[0].int)).toBe(4); // count + 1
    expect(json.fields[2].constructor).toBe(0n); // Some
    expect(json.fields[2].fields[0].fields[0].bytes).toBe("bb".repeat(32));
    expect(Number(json.fields[2].fields[0].fields[1].int)).toBe(0);
  });
});

describe("buildUpgradeTx guards", () => {
  it("throws when the owner is a script credential (no consent signer)", async () => {
    const registered: Registry = new Map([
      [counterScriptHash(counterV1Script(PARAMS)), "ee".repeat(28)],
    ]);
    await expect(
      buildUpgradeTx(
        upgradeTxParams(registered, {
          v1Utxo: counterUtxo(
            { count: 5, owner: SCRIPT_OWNER, prevInput: PREV_REF },
            1,
          ),
        }),
      ),
    ).rejects.toThrow(/owner to be a key/i);
  });

  it("throws when V1 is not registered in the registry", async () => {
    await expect(buildUpgradeTx(upgradeTxParams(new Map()))).rejects.toThrow(
      /not registered/i,
    );
  });

  it("throws when the migration script does not match the registry entry", async () => {
    const registered: Registry = new Map([
      [counterScriptHash(counterV1Script(PARAMS)), "ee".repeat(28)],
    ]);
    await expect(
      buildUpgradeTx(
        upgradeTxParams(registered, {
          migrationAuthorizer: { scriptCbor: counterV2Script().code },
        }),
      ),
    ).rejects.toThrow(/does not match the credential/i);
  });

  it("requires the owner signature and wires the migration withdraw-0 to V2", async () => {
    const migrationScript = counterMigrationScript({
      ...PARAMS,
      v2Address: V2_ADDR,
    });
    const registered: Registry = new Map([
      [
        counterScriptHash(counterV1Script(PARAMS)),
        counterScriptHash(migrationScript),
      ],
    ]);
    const { txBuilder, calls } = recorder();
    await buildUpgradeTx(upgradeTxParams(registered, { txBuilder }));

    const signer = calls.find((c) => c.method === "requiredSignerHash");
    expect(signer?.args[0]).toBe(OWNER.hash);

    const methods = calls.map((c) => c.method);
    expect(methods).toContain("readOnlyTxInReference");
    expect(methods).toContain("withdrawalPlutusScriptV3");
    expect(methods).toContain("withdrawalScript");

    const out = calls.find((c) => c.method === "txOut");
    expect(out?.args[0]).toBe(V2_ADDR);

    const datum = calls.find((c) => c.method === "txOutInlineDatumValue");
    const json = deserializeDatum(serializeData(datum?.args[0]));
    expect(Number(json.fields[0].int)).toBe(5); // count preserved
    expect(json.fields[2].constructor).toBe(0n); // Some
    expect(json.fields[2].fields[0].fields[0].bytes).toBe("bb".repeat(32));
    expect(Number(json.fields[2].fields[0].fields[1].int)).toBe(1); // v1Utxo index
  });
});

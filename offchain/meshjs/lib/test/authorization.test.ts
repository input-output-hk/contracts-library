import {
  applyCborEncoding,
  resolveScriptHash,
  serializeRewardAddress,
  type MeshTxBuilder,
} from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import { applyAuthorization } from "../src/authorization";
import { compiledCode, validatorHash } from "../src/blueprint";
import type { Credential } from "../src/types";

/** A MeshTxBuilder stand-in that records the methods called on it. */
function recorder() {
  const calls: { method: string; args: unknown[] }[] = [];
  const proxy: unknown = new Proxy(
    {},
    {
      get(_t, prop) {
        return (...args: unknown[]) => {
          calls.push({ method: String(prop), args });
          return proxy;
        };
      },
    },
  );
  return { txBuilder: proxy as MeshTxBuilder, calls };
}

const KEY_HASH = "ab".repeat(28);
const cbor = applyCborEncoding(compiledCode);
const SCRIPT_HASH = resolveScriptHash(cbor, "V3");

describe("applyAuthorization", () => {
  it("derives the same script hash the blueprint pins", () => {
    expect(SCRIPT_HASH).toBe(validatorHash);
  });

  it("key credential adds exactly a required signer", () => {
    const { txBuilder, calls } = recorder();
    const cred: Credential = { kind: "key", hash: KEY_HASH };
    applyAuthorization(txBuilder, cred, undefined, 0);
    expect(calls).toEqual([{ method: "requiredSignerHash", args: [KEY_HASH] }]);
  });

  it("script credential without an authorizer throws", () => {
    const { txBuilder } = recorder();
    const cred: Credential = { kind: "script", hash: SCRIPT_HASH };
    expect(() => applyAuthorization(txBuilder, cred, undefined, 0)).toThrow(
      /must be authorized by invoking/i,
    );
  });

  it("script credential with a mismatched authorizer hash throws", () => {
    const { txBuilder } = recorder();
    const cred: Credential = { kind: "script", hash: "00".repeat(28) };
    expect(() =>
      applyAuthorization(txBuilder, cred, { scriptCbor: cbor }, 0),
    ).toThrow(/does not match the credential/i);
  });

  it("manual authorizer wires nothing", () => {
    const { txBuilder, calls } = recorder();
    const cred: Credential = { kind: "script", hash: SCRIPT_HASH };
    applyAuthorization(txBuilder, cred, { manual: true }, 0);
    expect(calls).toEqual([]);
  });

  it("inline script authorizer wires the withdraw-0", () => {
    const { txBuilder, calls } = recorder();
    const cred: Credential = { kind: "script", hash: SCRIPT_HASH };
    applyAuthorization(txBuilder, cred, { scriptCbor: cbor }, 0);

    const methods = calls.map((c) => c.method);
    expect(methods).toEqual([
      "withdrawalPlutusScriptV3",
      "withdrawal",
      "withdrawalScript",
      "withdrawalRedeemerValue",
    ]);
    // withdraw exactly 0 from the script's reward address, derived from the hash
    expect(calls[1].args).toEqual([
      serializeRewardAddress(SCRIPT_HASH, true, 0),
      "0",
    ]);
    expect(calls[2].args).toEqual([cbor]);
  });
});

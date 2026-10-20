import type { Asset, MeshTxBuilder, PlutusScript, UTxO } from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import {
  buildWalletDepositTx,
  buildWalletUpdatePermissionsTx,
} from "../../src/smart_wallet/smart_wallet";

const WALLET_ADDRESS =
  "addr_test1qwalletbaseaddresswithstakecredential00000000000000000000000000000000000000000000000000000000";
const CHANGE_ADDRESS =
  "addr_test1qchangewalletbaseaddress00000000000000000000000000000000000000000000000000000000000000";

const script: PlutusScript = { code: "00", version: "V3" };

function walletUtxo(address = WALLET_ADDRESS): UTxO {
  return {
    input: { txHash: "00".repeat(32), outputIndex: 0 },
    output: {
      address,
      amount: [{ unit: "lovelace", quantity: "10000000" }],
    },
  } as UTxO;
}

function collateralUtxo(): UTxO {
  return {
    input: { txHash: "11".repeat(32), outputIndex: 0 },
    output: {
      address: CHANGE_ADDRESS,
      amount: [{ unit: "lovelace", quantity: "5000000" }],
    },
  } as UTxO;
}

function mockBuilder() {
  const captured: { address?: string; value?: Asset[] } = {};
  const builder = {
    requiredSignerHash: () => builder,
    spendingPlutusScriptV3: () => builder,
    txIn: () => builder,
    txInInlineDatumPresent: () => builder,
    txInRedeemerValue: () => builder,
    txInScript: () => builder,
    txOut: (address: string, value: Asset[]) => {
      captured.address = address;
      captured.value = value;
      return builder;
    },
    txOutInlineDatumValue: () => builder,
    txInCollateral: () => builder,
    changeAddress: () => builder,
    selectUtxosFrom: () => builder,
    complete: async () => "tx-hex",
  };
  return { builder: builder as unknown as MeshTxBuilder, captured };
}

describe("smart wallet builders reuse the wallet's full address", () => {
  it("Deposit writes the continuation to walletUtxo.output.address", async () => {
    const { builder, captured } = mockBuilder();
    await buildWalletDepositTx({
      txBuilder: builder,
      script,
      walletUtxo: walletUtxo(),
      datum: { spenders: [], depositors: [] },
      deposit: [{ unit: "lovelace", quantity: "2000000" }],
      outputIndex: 0,
      utxos: [],
      changeAddress: CHANGE_ADDRESS,
      collateralUtxo: collateralUtxo(),
    });
    expect(captured.address).toBe(WALLET_ADDRESS);
  });

  it("UpdatePermissions writes the continuation to walletUtxo.output.address", async () => {
    const { builder, captured } = mockBuilder();
    await buildWalletUpdatePermissionsTx({
      txBuilder: builder,
      script,
      walletUtxo: walletUtxo(),
      newDatum: { spenders: [], depositors: [] },
      outputIndex: 0,
      utxos: [],
      changeAddress: CHANGE_ADDRESS,
      collateralUtxo: collateralUtxo(),
      admin: { kind: "key", hash: "22".repeat(28) },
    });
    expect(captured.address).toBe(WALLET_ADDRESS);
  });

  it("UpdatePermissions can add the requested ADA top-up", async () => {
    const { builder, captured } = mockBuilder();
    await buildWalletUpdatePermissionsTx({
      txBuilder: builder,
      script,
      walletUtxo: walletUtxo(),
      newDatum: { spenders: [], depositors: [] },
      outputIndex: 0,
      utxos: [],
      changeAddress: CHANGE_ADDRESS,
      collateralUtxo: collateralUtxo(),
      admin: { kind: "key", hash: "22".repeat(28) },
      topUpLovelace: 2_000_000n,
    });
    expect(captured.address).toBe(WALLET_ADDRESS);
    expect(
      captured.value?.find((asset) => asset.unit === "lovelace")?.quantity,
    ).toBe("12000000");
  });
});

import { afterEach, beforeEach, expect, test } from "vitest";
import { TestDevnet, DEVNET_POLL, unwrapCborBytes } from "../../devnet/utils";
import {
  type SettingsParams,
  plutusVersion,
  settingsScript,
  settingsScriptAddress,
  SETTINGS_TOKEN_NAME,
} from "@contracts-library/meshjs";
import { Party } from "tx3-sdk";
import { Client } from "../.tx3/codegen/ts-client/config-parameter-management/protocol"; // trix codegen ts-client
import { resolveScriptHash, PlutusScript } from "@meshsdk/core";

const APPLY_DELAY = 4_000;
const VALUE_A = 1;
const VALUE_B = 2;

let devnet: TestDevnet;

// A fresh devnet per test: minting/burning the settings NFT mutates chain state,
// so isolation keeps each scenario deterministic.
beforeEach(async () => {
  devnet = await TestDevnet.start({
    wallets: {
      // Each signer needs two UTxOs: one to fund the transaction (mint seed /
      // gas) and a separate one reserved as script collateral.
      proposer: [10_000_000_000n, 5_000_000n],
      applier: [5_000_000_000n, 5_000_000n],
    },
  });
}, 60_000);
afterEach(() => devnet.stop());

interface Instance {
  client: Client;
  scriptAddr: string;
  scriptHash: string;
  /** Runtime overrides for the stale values baked into the `local` profile. */
  env: { settings_hash: string; settings_script: string; apply_delay: number };
  /** `txHash#index` of the applier UTxO consumed as the mint seed. */
  seedRef: string;
}

interface ConfigureOptions {
  proposerParty?: Party;
  applierParty?: Party;
}

/** Parameterize the settings script for this run and wire up a client. */
async function configure(options: ConfigureOptions = {}): Promise<Instance> {
  const proposer = devnet.wallet("proposer");
  const applier = devnet.wallet("applier");
  const seed = await devnet.seedUtxo("applier");

  const params: SettingsParams = {
    seedUtxo: { transactionId: seed.txHash, outputIndex: seed.outputIndex },
    proposeAuth: { kind: "key", hash: proposer.keyHash },
    applyAuth: { kind: "key", hash: applier.keyHash },
    applyDelay: APPLY_DELAY,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };

  const script: PlutusScript = settingsScript(params);
  const scriptHash = resolveScriptHash(script.code, plutusVersion);
  const scriptAddr = settingsScriptAddress(script);

  const client = new Client({ endpoint: devnet.trpUrl }, "local")
    .withProposer(options.proposerParty ?? proposer.party)
    .withApplier(options.applierParty ?? applier.party)
    .withSettings(Party.address(scriptAddr));

  return {
    client,
    scriptAddr,
    scriptHash,
    env: {
      settings_hash: scriptHash,
      // Must be the single-CBOR flat script (the mint/spend witness);
      // `applyParamsToScript` returns a double-CBOR wrapper, so strip one layer.
      settings_script: unwrapCborBytes(script.code),
      apply_delay: APPLY_DELAY,
    },
    seedRef: seed.ref,
  };
}

// The tx3 template's runtime arg names are snake_case, but the generated params
// types mistakenly declare camelCase — cast past them at each call site.
type LaunchArgs = Parameters<Client["launch"]>[0];
type ProposeArgs = Parameters<Client["propose"]>[0];
type ApplyArgs = Parameters<Client["apply"]>[0];
type CloseArgs = Parameters<Client["close"]>[0];
type CloseWithoutBurnAttackArgs = Parameters<
  Client["closeWithoutBurnAttack"]
>[0];

function launchTx(inst: Instance, value: number) {
  return inst.client
    .launch({
      seed: inst.seedRef,
      initial_value: value,
      out_ix: 0,
    } as unknown as LaunchArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function proposeTx(
  inst: Instance,
  newValue: number,
  nowMs: number,
  sinceSlot: number,
  outIx = 0,
) {
  return inst.client
    .propose({
      new_value: newValue,
      now_ms: nowMs,
      since_slot: sinceSlot,
      out_ix: outIx,
    } as unknown as ProposeArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function applyTx(
  inst: Instance,
  newCurrent: number,
  sinceSlot: number,
  outIx = 0,
) {
  return inst.client
    .apply({
      new_current: newCurrent,
      since_slot: sinceSlot,
      out_ix: outIx,
    } as unknown as ApplyArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function closeTx(inst: Instance) {
  return inst.client
    .close({} as unknown as CloseArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function closeWithoutBurnAttackTx(inst: Instance) {
  return inst.client
    .closeWithoutBurnAttack({} as unknown as CloseWithoutBurnAttackArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

/** Await a submitted transaction until the devnet confirms it. */
async function confirm(submitted: ReturnType<typeof launchTx>): Promise<void> {
  await (await submitted).waitForConfirmed(DEVNET_POLL);
}

/** Whether the settings NFT UTxO currently lives at the script address. */
async function settingsUtxoExists(inst: Instance): Promise<boolean> {
  return (await devnet.utxosOf(inst.scriptAddr)).length > 0;
}

// ------------------------------------------------------------- happy paths

test("launches a settings instance", async () => {
  const inst = await configure();

  await confirm(launchTx(inst, VALUE_A));

  expect(await settingsUtxoExists(inst)).toBe(true);
}, 60_000);

test("launches, proposes, applies, and closes", async () => {
  const inst = await configure();

  // 1. Launch — current = A.
  await confirm(launchTx(inst, VALUE_A));
  expect(await settingsUtxoExists(inst)).toBe(true);

  // 2. Propose — next = B, next_apply = now + apply_delay.
  const proposeTip = await devnet.tip();
  await confirm(proposeTx(inst, VALUE_B, proposeTip.timeMs, proposeTip.slot));
  const nextApplyMs = proposeTip.timeMs + APPLY_DELAY;

  // 3. Wait for the proposal to mature, then apply — current = B.
  await devnet.waitForChainTimeMs(nextApplyMs + 2_000);
  const applyTip = await devnet.tip();
  await confirm(applyTx(inst, VALUE_B, applyTip.slot));
  expect(await settingsUtxoExists(inst)).toBe(true);

  // 4. Close — burn the NFT and tear the instance down.
  await confirm(closeTx(inst));
  expect(await settingsUtxoExists(inst)).toBe(false);
}, 120_000);

// ------------------------------------------------------------- attack paths

test("rejects apply before next_apply", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  const proposeTip = await devnet.tip();
  await confirm(proposeTx(inst, VALUE_B, proposeTip.timeMs, proposeTip.slot));

  // Apply immediately, without waiting for the delay to elapse.
  const tip = await devnet.tip();
  await expect(applyTx(inst, VALUE_B, tip.slot)).rejects.toThrow();
}, 60_000);

test("rejects apply with no pending proposal", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  // Nothing was proposed, so there is no pending value to apply.
  const tip = await devnet.tip();
  await expect(applyTx(inst, VALUE_B, tip.slot)).rejects.toThrow();
}, 60_000);

test("rejects propose with same value as current", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  // Proposing the current value is a no-op the validator forbids.
  const tip = await devnet.tip();
  await expect(
    proposeTx(inst, VALUE_A, tip.timeMs, tip.slot),
  ).rejects.toThrow();
}, 60_000);

test("rejects propose signed by a non-proposer credential", async () => {
  const applier = devnet.wallet("applier");
  const inst = await configure({ proposerParty: applier.party });
  await confirm(launchTx(inst, VALUE_A));

  // Script params bind propose auth to `proposer`; using `applier` to propose
  // must fail validator authorization.
  const tip = await devnet.tip();
  await expect(
    proposeTx(inst, VALUE_B, tip.timeMs, tip.slot),
  ).rejects.toThrow();
}, 60_000);

test("rejects apply with an invalid continuation output index", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  const proposeTip = await devnet.tip();
  await confirm(proposeTx(inst, VALUE_B, proposeTip.timeMs, proposeTip.slot));
  const nextApplyMs = proposeTip.timeMs + APPLY_DELAY;

  await devnet.waitForChainTimeMs(nextApplyMs + 2_000);
  const applyTip = await devnet.tip();

  // `out_ix=1` points away from the continuation output in this tx layout.
  await expect(applyTx(inst, VALUE_B, applyTip.slot, 1)).rejects.toThrow();
}, 60_000);

test("rejects close without burning the settings NFT", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  await expect(closeWithoutBurnAttackTx(inst)).rejects.toThrow();
}, 60_000);

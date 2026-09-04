import { afterAll, beforeAll, beforeEach, expect, test } from "vitest";
import {
  TrixDevnet,
  DEVNET_POLL,
  unwrapCborBytes,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import {
  type SettingsParams,
  plutusVersion,
  settingsScript,
  settingsScriptAddress,
  SETTINGS_TOKEN_NAME,
} from "@contracts-library/meshjs";
import { Party } from "tx3-sdk";
import { Client } from "../codegen/ts-client/config-parameter-management/protocol"; // trix codegen ts-client
import {
  applyCborEncoding,
  resolveScriptHash,
  PlutusScript,
} from "@meshsdk/core";

const ADA = 1_000_000n;
// Must comfortably exceed ONE block interval (trix devnets mint every ~5s):
// an attack tx submitted early only reaches phase-2 in the NEXT block, and
// if the delay elapsed during mempool wait the validator rightly accepts it.
const APPLY_DELAY = 12_000;
// Per-test funding mirrors the old genesis layout: a large seed plus a
// separate reserved collateral UTxO per signer.
const PROPOSER_SEED = 10_000n * ADA;
const APPLIER_SEED = 5_000n * ADA;
const REGISTRAR_SEED = 10_000n * ADA;
const COLLATERAL = 5n * ADA;
const VALUE_A = new Uint8Array([1]);
const VALUE_B = new Uint8Array([2]);
const ALWAYS_TRUE_SCRIPT = "5101010023259800a518a4d136564004ae69";
const ALWAYS_TRUE_HASH = resolveScriptHash(
  applyCborEncoding(ALWAYS_TRUE_SCRIPT),
  plutusVersion,
);
// Script stake address BYTES for the always-true credential (network 0):
// CIP-19 header 0xf0 (script-cred reward account, testnet) + key hash.
const ALWAYS_TRUE_REWARD_ADDRESS = `f0${ALWAYS_TRUE_HASH}`;

let devnet: TrixDevnet;
let authorizerRef: DevnetUtxo;
let proposer!: DevnetWallet;
let applier!: DevnetWallet;

// One ephemeral devnet for the whole suite (trix owns the node lifecycle).
// Chain state persists between tests, so every test funds its OWN wallets —
// unique random keys make instances independent regardless of test order.
beforeAll(async () => {
  devnet = await TrixDevnet.start();

  const registrar = devnet.wallet("bootstrap/registrar");
  await devnet.payTo(registrar.address, REGISTRAR_SEED);
  await devnet.payTo(registrar.address, COLLATERAL);
  authorizerRef = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode: ALWAYS_TRUE_SCRIPT,
    lovelace: 2n * ADA,
  });
  // Stake registration is global chain state: once is enough for every
  // script-authorized test below.
  await devnet.registerScriptStakeCredential(registrar, ALWAYS_TRUE_HASH);
}, 180_000);

afterAll(() => devnet.stop());

beforeEach(async () => {
  proposer = devnet.wallet("proposer");
  applier = devnet.wallet("applier");
  await devnet.payTo(proposer.address, PROPOSER_SEED);
  await devnet.payTo(proposer.address, COLLATERAL);
  await devnet.payTo(applier.address, APPLIER_SEED);
  await devnet.payTo(applier.address, COLLATERAL);
}, 120_000);

interface Instance {
  client: Client;
  scriptAddr: string;
  scriptHash: string;
  /** Runtime overrides for the stale values baked into the `local` profile. */
  env: {
    settings_hash: string;
    settings_script: string;
    apply_delay: number;
    proposer_script_ref: string;
    proposer_script_address: string;
    applier_script_ref: string;
    applier_script_address: string;
  };
  /** `txHash#index` of the applier UTxO consumed as the mint seed. */
  seedRef: string;
}

interface ConfigureOptions {
  proposerParty?: Party;
  applierParty?: Party;
  scriptAuthorized?: boolean;
}

/** Parameterize the settings script for this run and wire up a client. */
async function configure(options: ConfigureOptions = {}): Promise<Instance> {
  const seed = await devnet.seedUtxo(applier);

  const params: SettingsParams = {
    seedUtxo: { txHash: seed.txHash, outputIndex: seed.outputIndex },
    proposeAuth: options.scriptAuthorized
      ? { kind: "script", hash: ALWAYS_TRUE_HASH }
      : { kind: "key", hash: proposer.keyHash },
    applyAuth: options.scriptAuthorized
      ? { kind: "script", hash: ALWAYS_TRUE_HASH }
      : { kind: "key", hash: applier.keyHash },
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
      proposer_script_ref: authorizerRef.ref,
      proposer_script_address: ALWAYS_TRUE_REWARD_ADDRESS,
      applier_script_ref: authorizerRef.ref,
      applier_script_address: ALWAYS_TRUE_REWARD_ADDRESS,
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
type LaunchScriptAuthorizedArgs = Parameters<
  Client["launchScriptAuthorized"]
>[0];
type ProposeScriptAuthorizedArgs = Parameters<
  Client["proposeScriptAuthorized"]
>[0];
type ApplyScriptAuthorizedArgs = Parameters<Client["applyScriptAuthorized"]>[0];
type CloseScriptAuthorizedArgs = Parameters<Client["closeScriptAuthorized"]>[0];
type CloseWithoutBurnAttackScriptAuthorizedArgs = Parameters<
  Client["closeWithoutBurnAttackScriptAuthorized"]
>[0];

function launchTx(inst: Instance, value: Uint8Array) {
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
  newValue: Uint8Array,
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
  newCurrent: Uint8Array,
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

function launchScriptAuthorizedTx(inst: Instance, value: Uint8Array) {
  return inst.client
    .launchScriptAuthorized({
      seed: inst.seedRef,
      initial_value: value,
      out_ix: 0,
    } as unknown as LaunchScriptAuthorizedArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function proposeScriptAuthorizedTx(
  inst: Instance,
  newValue: Uint8Array,
  nowMs: number,
  sinceSlot: number,
) {
  return inst.client
    .proposeScriptAuthorized({
      new_value: newValue,
      now_ms: nowMs,
      since_slot: sinceSlot,
      out_ix: 0,
    } as unknown as ProposeScriptAuthorizedArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function applyScriptAuthorizedTx(
  inst: Instance,
  newCurrent: Uint8Array,
  sinceSlot: number,
) {
  return inst.client
    .applyScriptAuthorized({
      new_current: newCurrent,
      since_slot: sinceSlot,
      out_ix: 0,
    } as unknown as ApplyScriptAuthorizedArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function closeScriptAuthorizedTx(inst: Instance) {
  return inst.client
    .closeScriptAuthorized({} as CloseScriptAuthorizedArgs)
    .env(inst.env)
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

function closeWithoutBurnAttackScriptAuthorizedTx(inst: Instance) {
  return inst.client
    .closeWithoutBurnAttackScriptAuthorized(
      {} as CloseWithoutBurnAttackScriptAuthorizedArgs,
    )
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

/**
 * A rejected attack must fail for the RIGHT reason (ledger phase-2 script /
 * validity failure surfaced through TRP) and must leave the settings instance
 * untouched — a generic throw would also catch unrelated build-time failures
 * and prove nothing about the validator.
 */
async function expectAttackRejected(
  attack: Promise<unknown>,
  inst: Instance,
): Promise<void> {
  let message = "";
  await expect(
    attack.catch((err: unknown) => {
      message = err instanceof Error ? err.message : String(err);
      throw err;
    }),
  ).rejects.toThrow();
  expect(message).toMatch(/script returned failure|-32003|invalid|evaluat/i);
  expect(await settingsUtxoExists(inst)).toBe(true);
}

// ------------------------------------------------------------- happy paths

test("launches a settings instance", async () => {
  const inst = await configure();

  await confirm(launchTx(inst, VALUE_A));

  expect(await settingsUtxoExists(inst)).toBe(true);
}, 120_000);

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
  await devnet.waitForChainTimeMs(nextApplyMs + 3_000);
  const applyTip = await devnet.tip();
  await confirm(applyTx(inst, VALUE_B, applyTip.slot));
  expect(await settingsUtxoExists(inst)).toBe(true);

  // 4. Close — burn the NFT and tear the instance down.
  await confirm(closeTx(inst));
  expect(await settingsUtxoExists(inst)).toBe(false);
}, 240_000);

// The script-authorized variants authorize through a withdraw-0 keyed by the
// always-true reference script deployed in beforeAll.
test("runs the script-authorized lifecycle", async () => {
  const inst = await configure({ scriptAuthorized: true });

  await confirm(launchScriptAuthorizedTx(inst, VALUE_A));
  expect(await settingsUtxoExists(inst)).toBe(true);

  const proposeTip = await devnet.tip();
  await confirm(
    proposeScriptAuthorizedTx(
      inst,
      VALUE_B,
      proposeTip.timeMs,
      proposeTip.slot,
    ),
  );

  await devnet.waitForChainTimeMs(proposeTip.timeMs + APPLY_DELAY + 3_000);
  const applyTip = await devnet.tip();
  await confirm(applyScriptAuthorizedTx(inst, VALUE_B, applyTip.slot));
  expect(await settingsUtxoExists(inst)).toBe(true);

  await confirm(closeScriptAuthorizedTx(inst));
  expect(await settingsUtxoExists(inst)).toBe(false);
}, 240_000);

// ------------------------------------------------------------- attack paths

test("rejects apply before next_apply", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  const proposeTip = await devnet.tip();
  await confirm(proposeTx(inst, VALUE_B, proposeTip.timeMs, proposeTip.slot));

  // Apply immediately, without waiting for the delay to elapse.
  const tip = await devnet.tip();
  await expectAttackRejected(applyTx(inst, VALUE_B, tip.slot), inst);
}, 120_000);

test("rejects apply with no pending proposal", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  // Nothing was proposed, so there is no pending value to apply.
  const tip = await devnet.tip();
  await expectAttackRejected(applyTx(inst, VALUE_B, tip.slot), inst);
}, 120_000);

test("rejects propose with same value as current", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  // Proposing the current value is a no-op the validator forbids.
  const tip = await devnet.tip();
  await expectAttackRejected(
    proposeTx(inst, VALUE_A, tip.timeMs, tip.slot),
    inst,
  );
}, 120_000);

test("rejects propose signed by a non-proposer credential", async () => {
  const inst = await configure({ proposerParty: applier.party });
  await confirm(launchTx(inst, VALUE_A));

  // Script params bind propose auth to `proposer`; using `applier` to propose
  // must fail validator authorization.
  const tip = await devnet.tip();
  await expectAttackRejected(
    proposeTx(inst, VALUE_B, tip.timeMs, tip.slot),
    inst,
  );
}, 120_000);

test("rejects apply with an invalid continuation output index", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  const proposeTip = await devnet.tip();
  await confirm(proposeTx(inst, VALUE_B, proposeTip.timeMs, proposeTip.slot));
  const nextApplyMs = proposeTip.timeMs + APPLY_DELAY;

  await devnet.waitForChainTimeMs(nextApplyMs + 3_000);
  const applyTip = await devnet.tip();

  // `out_ix=1` points away from the continuation output in this tx layout.
  await expectAttackRejected(applyTx(inst, VALUE_B, applyTip.slot, 1), inst);
}, 120_000);

test("rejects close without burning the settings NFT", async () => {
  const inst = await configure();
  await confirm(launchTx(inst, VALUE_A));

  await expectAttackRejected(closeWithoutBurnAttackTx(inst), inst);
}, 120_000);

test("rejects script-authorized close without burning the settings NFT", async () => {
  const inst = await configure({ scriptAuthorized: true });
  await confirm(launchScriptAuthorizedTx(inst, VALUE_A));

  await expectAttackRejected(
    closeWithoutBurnAttackScriptAuthorizedTx(inst),
    inst,
  );
}, 120_000);

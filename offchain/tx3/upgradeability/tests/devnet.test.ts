import { afterAll, beforeAll, expect, test } from "vitest";
import {
  TrixDevnet,
  DEVNET_POLL,
  unwrapCborBytes,
  type DevnetKitFactory,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import {
  SETTINGS_TOKEN_NAME,
  counterForwarderScript,
  counterLogicScript,
  counterMigrationScript,
  counterScriptAddress,
  counterScriptHash,
  counterV1Script,
  counterV2Script,
  settingsScript,
  settingsScriptAddress,
  type SettingsParams,
} from "@contracts-library/meshjs";
import { resolveScriptHash } from "@meshsdk/core";
import { Party, type SubmittedTx, type TxBuilder } from "tx3-sdk";
import { Client } from "../codegen/ts-client/upgradeability/protocol";

const ADA = 1_000_000n;
// Must comfortably exceed ONE block interval (trix devnets mint every ~5s):
// an attack tx submitted early only reaches phase-2 in the NEXT block, and
// if the delay elapsed during mempool wait the validator rightly accepts it.
const APPLY_DELAY = 12_000;
const GOVERNOR_FUNDS = 12n * ADA;
const OWNER_GAS = 10n * ADA;
const COLLATERAL = 5n * ADA;
const REGISTRAR_FUNDS = 30n * ADA;

const toBytes = (hex: string): Uint8Array => Buffer.from(hex, "hex");

/** The spent UTxO as the on-chain `OutputReference` (datum tag). */
const prevOf = (utxo: DevnetUtxo) => ({
  transaction_id: toBytes(utxo.txHash),
  output_index: utxo.outputIndex,
});

/** Dummy env satisfying the protocol's declared env for test-kit txs. */
const KIT_ENV = {
  settings_hash: "00",
  settings_script: "00",
  apply_delay: 0,
  forwarder_hash: "00",
  forwarder_script: "00",
  v1_hash: "00",
  v1_script: "00",
  v2_script: "00",
  logic_script_ref: "00#0",
  logic_reward_address: "00",
  migration_script_ref: "00#0",
  migration_reward_address: "00",
};

const upgradeabilityKit: DevnetKitFactory = (trpUrl, faucet) => {
  const kitClient = () =>
    new Client({ endpoint: trpUrl }, "local").withFaucet(faucet);
  return {
    pay: async (address, quantity) => {
      const submitted = await kitClient()
        .devnetPay({ destination: address, quantity: Number(quantity) })
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
    deploy: async (publisherAddress, scriptCode, lovelace) => {
      const submitted = await kitClient()
        .withPublisher(Party.address(publisherAddress))
        .devnetDeployAuthorizer({
          // Runtime args are snake_case; the generated param type says camelCase.
          script_code: Buffer.from(scriptCode, "hex"),
          lovelace: Number(lovelace),
        } as unknown as Parameters<Client["devnetDeployAuthorizer"]>[0])
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
  };
};

let devnet: TrixDevnet;
let registrar: DevnetWallet;
let governor: DevnetWallet;
let owner: DevnetWallet;

interface Instance {
  client: (signer: DevnetWallet) => Client;
  env: Record<string, unknown>;
  settingsAddr: string;
  settingsRef: string;
  forwarderAddr: string;
  v1Addr: string;
  v2Addr: string;
  forwarderHash: string;
  logicHash: string;
  v1Hash: string;
  migrationHash: string;
  migrationRef: DevnetUtxo;
}

let inst: Instance;
/** The forwarder UTxO the forced-tick tests spend and carry forward. */
let forwarderUtxo: DevnetUtxo;
/** The V1 UTxO the native tick spends and carries forward. */
let v1Utxo: DevnetUtxo;

// --------------------------------------------------------------- harness

/** resolve → sign → submit, without waiting for confirmation. */
function submit(builder: TxBuilder): Promise<SubmittedTx> {
  return builder
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

/** Submit a transaction and wait until the devnet confirms it. */
async function confirm(builder: TxBuilder): Promise<void> {
  await (await submit(builder)).waitForConfirmed(DEVNET_POLL);
}

/**
 * A rejected attack must fail for the RIGHT reason (ledger phase-2 script
 * failure surfaced through TRP) and must leave the guarded UTxOs untouched — a
 * generic throw would also catch unrelated build-time failures and prove
 * nothing about the validator.
 */
async function expectAttackRejected(
  attack: Promise<unknown>,
  guards: DevnetUtxo[],
  guardAddress: string,
): Promise<void> {
  let message = "";
  await expect(
    attack.catch((err: unknown) => {
      message = err instanceof Error ? err.message : String(err);
      throw err;
    }),
  ).rejects.toThrow();
  expect(message).toMatch(/script returned failure|-32003|invalid|evaluat/i);
  const live = await devnet.utxosOf(guardAddress);
  for (const guard of guards) {
    expect(
      live.some((u) => u.ref === guard.ref),
      `guarded utxo ${guard.ref} was spent`,
    ).toBe(true);
  }
}

async function snapshot(address: string): Promise<Set<string>> {
  return new Set((await devnet.utxosOf(address)).map((u) => u.ref));
}

async function addedSince(
  address: string,
  before: Set<string>,
): Promise<DevnetUtxo[]> {
  return (await devnet.utxosOf(address)).filter((u) => !before.has(u.ref));
}

// Generated param types declare camelCase while the runtime expects
// snake_case; cast past them at each call site.
type LaunchRegistryArgs = Parameters<Client["launchRegistry"]>[0];
type ProposeRegistryArgs = Parameters<Client["proposeRegistry"]>[0];
type ApplyRegistryArgs = Parameters<Client["applyRegistry"]>[0];
type LockForwarderArgs = Parameters<Client["lockForwarder"]>[0];
type LockV1Args = Parameters<Client["lockV1"]>[0];
type TickForwarderArgs = Parameters<Client["tickForwarder"]>[0];
type TickV1Args = Parameters<Client["tickV1"]>[0];
type TickV2Args = Parameters<Client["tickV2"]>[0];
type MigrateV1Args = Parameters<Client["migrateV1"]>[0];
type MigrateTamperedCountAttackArgs = Parameters<
  Client["migrateTamperedCountAttack"]
>[0];
type MigrateWrongTargetAttackArgs = Parameters<
  Client["migrateWrongTargetAttack"]
>[0];
type MigrateWrongActionAttackArgs = Parameters<
  Client["migrateWrongActionAttack"]
>[0];

// --------------------------------------------------------------- setup

async function setup(): Promise<Instance> {
  governor = devnet.wallet("governor");
  owner = devnet.wallet("owner");
  await devnet.payTo(governor.address, GOVERNOR_FUNDS);
  await devnet.payTo(governor.address, COLLATERAL);
  // Several large UTxOs: every lock needs one ≥ 3 ADA + fees, and script fees
  // fragment the owner's change as the suite progresses.
  for (let i = 0; i < 4; i++) {
    await devnet.payTo(owner.address, OWNER_GAS);
  }
  await devnet.payTo(owner.address, COLLATERAL);

  const seed = await devnet.seedUtxo(governor);
  const settingsParams: SettingsParams = {
    seedUtxo: { txHash: seed.txHash, outputIndex: seed.outputIndex },
    proposeAuth: { kind: "key", hash: governor.keyHash },
    applyAuth: { kind: "key", hash: governor.keyHash },
    applyDelay: APPLY_DELAY,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };
  const settingsScriptObj = settingsScript(settingsParams);
  const settingsHash = resolveScriptHash(settingsScriptObj.code, "V3");
  const settingsAddr = settingsScriptAddress(settingsScriptObj);

  const counterParams = {
    settingsPolicy: settingsHash,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };
  const forwarderScriptObj = counterForwarderScript(counterParams);
  const logicScriptObj = counterLogicScript(counterParams);
  const v1ScriptObj = counterV1Script(counterParams);
  const v2ScriptObj = counterV2Script();
  const forwarderHash = counterScriptHash(forwarderScriptObj);
  const logicHash = counterScriptHash(logicScriptObj);
  const v1Hash = counterScriptHash(v1ScriptObj);
  const forwarderAddr = counterScriptAddress(forwarderScriptObj, 0);
  const v1Addr = counterScriptAddress(v1ScriptObj, 0);
  const v2Addr = counterScriptAddress(v2ScriptObj, 0);
  const migrationScriptObj = counterMigrationScript({
    ...counterParams,
    v2Address: v2Addr,
  });
  const migrationHash = counterScriptHash(migrationScriptObj);

  // Register the withdraw-0 stake credentials BEFORE publishing any reference
  // script: the harness spends the registrar's first UTxO to pay the
  // registration fee, and a reference-script output must never be picked.
  await devnet.registerScriptStakeCredential(registrar, logicHash);
  await devnet.registerScriptStakeCredential(registrar, migrationHash);

  const logicRef = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode: unwrapCborBytes(logicScriptObj.code),
    lovelace: 2n * ADA,
  });
  const migrationRef = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode: unwrapCborBytes(migrationScriptObj.code),
    lovelace: 2n * ADA,
  });

  const env = {
    settings_hash: settingsHash,
    settings_script: unwrapCborBytes(settingsScriptObj.code),
    apply_delay: APPLY_DELAY,
    forwarder_hash: forwarderHash,
    forwarder_script: unwrapCborBytes(forwarderScriptObj.code),
    v1_hash: v1Hash,
    v1_script: unwrapCborBytes(v1ScriptObj.code),
    v2_script: unwrapCborBytes(v2ScriptObj.code),
    logic_script_ref: logicRef.ref,
    logic_reward_address: `f0${logicHash}`,
    migration_script_ref: migrationRef.ref,
    migration_reward_address: `f0${migrationHash}`,
  };

  const client = (signer: DevnetWallet) =>
    new Client({ endpoint: devnet.trpUrl }, "local")
      .withGovernor(governor.party)
      .withSigner(signer.party)
      .withSettings(Party.address(settingsAddr))
      .withForwarder(Party.address(forwarderAddr))
      .withV1(Party.address(v1Addr))
      .withV2(Party.address(v2Addr));

  await confirm(
    client(governor)
      .launchRegistry({
        seed: seed.ref,
        entry_1_key: toBytes(forwarderHash),
        entry_1_value: toBytes(logicHash),
        entry_2_key: toBytes(v1Hash),
        entry_2_value: toBytes(migrationHash),
        out_ix: 0,
      } as unknown as LaunchRegistryArgs)
      .env(env),
  );

  const settingsRef = (await devnet.utxosOf(settingsAddr))[0].ref;

  return {
    client,
    env,
    settingsAddr,
    settingsRef,
    forwarderAddr,
    v1Addr,
    v2Addr,
    forwarderHash,
    logicHash,
    v1Hash,
    migrationHash,
    migrationRef,
  };
}

async function lockCounter(
  target: "forwarder" | "v1",
  count: number,
  ownerKeyHash: string,
): Promise<DevnetUtxo> {
  const addr = target === "forwarder" ? inst.forwarderAddr : inst.v1Addr;
  const before = await snapshot(addr);
  const ownerArg = { Key: { hash: toBytes(ownerKeyHash) } };
  if (target === "forwarder") {
    await confirm(
      inst
        .client(owner)
        .lockForwarder({
          count,
          owner: ownerArg,
        } as unknown as LockForwarderArgs)
        .env(inst.env),
    );
  } else {
    await confirm(
      inst
        .client(owner)
        .lockV1({ count, owner: ownerArg } as unknown as LockV1Args)
        .env(inst.env),
    );
  }
  const [utxo] = await addedSince(addr, before);
  if (!utxo) throw new Error(`lock ${target} confirmed but no UTxO appeared`);
  return utxo;
}

/** Propose a registry change for the forwarder's entry (V1 stays put). */
async function proposeRegistry(forwarderValue: string): Promise<number> {
  const tip = await devnet.tip();
  await confirm(
    inst
      .client(governor)
      .proposeRegistry({
        entry_1_key: toBytes(inst.forwarderHash),
        entry_1_value: toBytes(forwarderValue),
        entry_2_key: toBytes(inst.v1Hash),
        entry_2_value: toBytes(inst.migrationHash),
        now_ms: tip.timeMs,
        since_slot: tip.slot,
        out_ix: 0,
      } as unknown as ProposeRegistryArgs)
      .env(inst.env),
  );
  return tip.timeMs + APPLY_DELAY;
}

/** Wait out the timelock and apply the pending registry proposal. */
async function applyRegistry(
  forwarderValue: string,
  nextApplyMs: number,
): Promise<void> {
  await devnet.waitForChainTimeMs(nextApplyMs + 3_000);
  const tip = await devnet.tip();
  await confirm(
    inst
      .client(governor)
      .applyRegistry({
        entry_1_key: toBytes(inst.forwarderHash),
        entry_1_value: toBytes(forwarderValue),
        entry_2_key: toBytes(inst.v1Hash),
        entry_2_value: toBytes(inst.migrationHash),
        since_slot: tip.slot,
        out_ix: 0,
      } as unknown as ApplyRegistryArgs)
      .env(inst.env),
  );
  // Every registry change recreates the settings UTxO: refresh the ref every
  // consumer must pass as a reference input.
  inst.settingsRef = (await devnet.utxosOf(inst.settingsAddr))[0].ref;
}

async function repointForwarder(forwarderValue: string): Promise<void> {
  const nextApplyMs = await proposeRegistry(forwarderValue);
  await applyRegistry(forwarderValue, nextApplyMs);
}

// --------------------------------------------------------------- suite

beforeAll(async () => {
  devnet = await TrixDevnet.start({
    protocolRoot: "upgradeability",
    kit: upgradeabilityKit,
  });

  // Registrar pays the two stake registrations; the reference scripts are
  // published afterwards so its first UTxO is never a reference-script output.
  registrar = devnet.wallet("bootstrap/registrar");
  await devnet.payTo(registrar.address, REGISTRAR_FUNDS);

  inst = await setup();
  forwarderUtxo = await lockCounter("forwarder", 1, owner.keyHash);
  v1Utxo = await lockCounter("v1", 5, owner.keyHash);
}, 300_000);

afterAll(() => devnet.stop());

test("launches the registry and ticks the forwarder through the registered logic", async () => {
  expect((await devnet.utxosOf(inst.settingsAddr)).length).toBe(1);

  const before = await snapshot(inst.forwarderAddr);
  await confirm(
    inst
      .client(owner)
      .tickForwarder({
        forwarder_ref: forwarderUtxo.ref,
        prev_ref: prevOf(forwarderUtxo),
        settings_ref: inst.settingsRef,
      } as unknown as TickForwarderArgs)
      .env(inst.env),
  );

  const [continuation] = await addedSince(inst.forwarderAddr, before);
  expect(continuation).toBeDefined();
  expect(
    (await devnet.utxosOf(inst.forwarderAddr)).some(
      (u) => u.ref === forwarderUtxo.ref,
    ),
  ).toBe(false);
  forwarderUtxo = continuation;
}, 120_000);

test("ticks V1 natively without consulting the registry", async () => {
  const before = await snapshot(inst.v1Addr);
  await confirm(
    inst
      .client(owner)
      .tickV1({
        counter_ref: v1Utxo.ref,
        prev_ref: prevOf(v1Utxo),
      } as unknown as TickV1Args)
      .env(inst.env),
  );

  const [continuation] = await addedSince(inst.v1Addr, before);
  expect(continuation).toBeDefined();
  expect(
    (await devnet.utxosOf(inst.v1Addr)).some((u) => u.ref === v1Utxo.ref),
  ).toBe(false);
  v1Utxo = continuation;
}, 120_000);

test("migrates a V1 UTxO to V2 with the owner's consent, and ticks V2 natively", async () => {
  const v1 = await lockCounter("v1", 7, owner.keyHash);

  const beforeV2 = await snapshot(inst.v2Addr);
  await confirm(
    inst
      .client(owner)
      .migrateV1({
        v1_ref: v1.ref,
        prev_ref: prevOf(v1),
        settings_ref: inst.settingsRef,
      } as unknown as MigrateV1Args)
      .env(inst.env),
  );

  const [v2] = await addedSince(inst.v2Addr, beforeV2);
  expect(v2).toBeDefined();
  expect(
    (await devnet.utxosOf(inst.v1Addr)).some((u) => u.ref === v1.ref),
  ).toBe(false);

  const beforeTick = await snapshot(inst.v2Addr);
  await confirm(
    inst
      .client(owner)
      .tickV2({ counter_ref: v2.ref } as unknown as TickV2Args)
      .env(inst.env),
  );
  const [continued] = await addedSince(inst.v2Addr, beforeTick);
  expect(continued).toBeDefined();
  expect(
    (await devnet.utxosOf(inst.v2Addr)).some((u) => u.ref === v2.ref),
  ).toBe(false);
}, 180_000);

test("rejects a migration without the owner's consent", async () => {
  // The UTxO is owned by the governor; the owner party signs, so the consent
  // witness the V1 validator checks for is missing.
  const v1 = await lockCounter("v1", 1, governor.keyHash);
  await expectAttackRejected(
    submit(
      inst
        .client(owner)
        .migrateV1({
          v1_ref: v1.ref,
          prev_ref: prevOf(v1),
          settings_ref: inst.settingsRef,
        } as unknown as MigrateV1Args)
        .env(inst.env),
    ),
    [v1],
    inst.v1Addr,
  );
}, 120_000);

test("rejects a migration that tampers with the migrated count", async () => {
  const v1 = await lockCounter("v1", 3, owner.keyHash);
  await expectAttackRejected(
    submit(
      inst
        .client(owner)
        .migrateTamperedCountAttack({
          v1_ref: v1.ref,
          prev_ref: prevOf(v1),
          settings_ref: inst.settingsRef,
          count: 4,
        } as unknown as MigrateTamperedCountAttackArgs)
        .env(inst.env),
    ),
    [v1],
    inst.v1Addr,
  );
}, 120_000);

test("rejects a migration whose continuation stays at the V1 address", async () => {
  const v1 = await lockCounter("v1", 2, owner.keyHash);
  await expectAttackRejected(
    submit(
      inst
        .client(owner)
        .migrateWrongTargetAttack({
          v1_ref: v1.ref,
          prev_ref: prevOf(v1),
          settings_ref: inst.settingsRef,
        } as unknown as MigrateWrongTargetAttackArgs)
        .env(inst.env),
    ),
    [v1],
    inst.v1Addr,
  );
}, 120_000);

test("rejects a V1 spent with Tick while the migration script runs", async () => {
  const v1 = await lockCounter("v1", 4, owner.keyHash);
  await expectAttackRejected(
    submit(
      inst
        .client(owner)
        .migrateWrongActionAttack({
          v1_ref: v1.ref,
          prev_ref: prevOf(v1),
          settings_ref: inst.settingsRef,
        } as unknown as MigrateWrongActionAttackArgs)
        .env(inst.env),
    ),
    [v1],
    inst.v1Addr,
  );
}, 120_000);

test("repoints the registry and a tick routed to the migration script is rejected on-chain", async () => {
  await repointForwarder(inst.migrationHash);

  // The registry now names the migration script for the forwarder: a tick
  // withdraws from it, but it demands the Upgrade action, so phase-2 rejects.
  const migrationEnv = {
    ...inst.env,
    logic_script_ref: inst.migrationRef.ref,
    logic_reward_address: `f0${inst.migrationHash}`,
  };
  await expectAttackRejected(
    submit(
      inst
        .client(owner)
        .tickForwarder({
          forwarder_ref: forwarderUtxo.ref,
          prev_ref: prevOf(forwarderUtxo),
          settings_ref: inst.settingsRef,
        } as unknown as TickForwarderArgs)
        .env(migrationEnv),
    ),
    [forwarderUtxo],
    inst.forwarderAddr,
  );

  await repointForwarder(inst.logicHash);
  const before = await snapshot(inst.forwarderAddr);
  await confirm(
    inst
      .client(owner)
      .tickForwarder({
        forwarder_ref: forwarderUtxo.ref,
        prev_ref: prevOf(forwarderUtxo),
        settings_ref: inst.settingsRef,
      } as unknown as TickForwarderArgs)
      .env(inst.env),
  );
  const [continuation] = await addedSince(inst.forwarderAddr, before);
  expect(continuation).toBeDefined();
  forwarderUtxo = continuation;
}, 300_000);

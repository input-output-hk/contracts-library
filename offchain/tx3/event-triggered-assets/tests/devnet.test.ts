/**
 * Real-world happy paths for the tokenized bond over the vendored CIP-113 core
 * (cardano-foundation/cip113-programmable-tokens): deploy the core through the
 * tx3 test kit, register + issue the bond through the core registry, then drive
 * the transfer -> transform -> graduate lifecycle — including the
 * third-party (permissionless) graduation — against a trix devnet.
 *
 * Single-signer discipline: the tx signer must be the credential the protocol
 * requires, so each step rebinds the generated client's `Signer` party.
 */

import { afterAll, beforeAll, expect, test } from "vitest";
import { type TxBuilder } from "tx3-sdk";

import {
  DEVNET_POLL,
  TrixDevnet,
  unwrapCborBytes,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import { Client } from "../codegen/ts-client/tokenized-bond/protocol";
import {
  type BondScripts,
  type CoreScripts,
  applyCoreScripts,
  baseAddr,
  bondScripts,
  bytes,
  hexOf,
  issuanceMintCompiledCode,
  issuanceTemplate,
  plbAddr,
  refIndexOf,
  refParts,
  rewardAddrHex,
  scriptAddr,
  scriptHashOf,
  sortRefs,
  withdrawalIndexOf,
} from "./cip113";

const ADA = 1_000_000n;

const PRINCIPAL = "424f4e44"; // "BOND"
const REFERENCE = "524546323232"; // "REF222"
const SCALE = 1000;
const QUANTITY = 1000n;
const SENTINEL_NEXT = "ff".repeat(30);
const MAX_INLINE_DATUM_BYTES = 1024;
const ALWAYS_FAIL_NONCE = "ab".repeat(32);

// --------------------------------------------------------------- harness glue

let devnet: TrixDevnet;
/** Publishes reference-script UTxOs (never used as a tx signer). */
let registrar: DevnetWallet;
/** Registers stake credentials (never holds reference-script UTxOs). */
let registrant: DevnetWallet;
let core: CoreScripts;
let registryAddr: string;
let paramsRef: string;
/** Filled once the upgrade-multisig reference script is published. */
let upgradeMultisigScriptRef = "00#0";
/** Filled once the issuance-template reference NFT is locked. */
let cborHexRef = "00#0";
let coreRefs: {
  plbGlobal: string;
  coreTransfer: string;
  coreThirdParty: string;
  coreIssuance: string;
};

interface NodeState {
  ref: string;
  datum: Record<string, unknown>;
}

/** Registry linked-list nodes we created, tracked across instruments. */
const registryNodes: NodeState[] = [];

function clientFor(signer: DevnetWallet) {
  return new Client({ endpoint: devnet.trpUrl }, "local").withSigner(
    signer.party,
  );
}

/** Resolve, sign, submit, and wait until the devnet confirms. */
async function confirm(builder: TxBuilder): Promise<string> {
  const resolved = await builder.resolve();
  try {
    const submitted = await resolved.sign().then((s) => s.submit());
    await submitted.waitForConfirmed(DEVNET_POLL);
    return submitted.hash;
  } catch (err) {
    const diagnostic = (err as { diagnostic?: unknown }).diagnostic;
    if (diagnostic !== undefined) {
      console.error(
        `[debug] script failure diagnostic: ${JSON.stringify(diagnostic)}`,
      );
    }
    if (process.env.DEBUG_TX) {
      console.error(`[debug] resolved tx ${resolved.hash}: ${resolved.txHex}`);
    }
    throw err;
  }
}

const snapshot = async (address: string): Promise<Set<string>> =>
  new Set((await devnet.utxosOf(address)).map((u) => u.ref));

const addedSince = async (
  address: string,
  before: Set<string>,
): Promise<DevnetUtxo[]> =>
  (await devnet.utxosOf(address)).filter((u) => !before.has(u.ref));

const one = (utxos: DevnetUtxo[], what: string): DevnetUtxo => {
  if (utxos.length !== 1)
    throw new Error(`expected exactly one ${what} UTxO, got ${utxos.length}`);
  return utxos[0];
};

async function deployReferenceScript(scriptCode: string): Promise<string> {
  const utxo = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode,
    lovelace: 2n * ADA,
  });
  return utxo.ref;
}

// -------------------------------------------------------------------- bootstrap

const emptyVKey = { Key: { hash: new Uint8Array(0) } };

function bootstrapEnv(): Record<string, unknown> {
  return {
    // Environment Bytes values travel as hex strings: the SDK only types the
    // transaction's own args, not the protocol environment.
    // Per-instrument placeholders (unused by the bootstrap txs).
    cip_policy: "00".repeat(28),
    cip_policy_script: "00",
    native_policy: "00".repeat(28),
    native_mint_script: "00",
    issuance_script_ref: "00#0",
    issuance_script_address: "00",
    transfer_logic_script_ref: "00#0",
    transfer_logic_script_address: "00",
    third_party_logic_script_ref: "00#0",
    third_party_logic_script_address: "00",
    transformation_script_ref: "00#0",
    transformation_script_address: "00",
    issuance_hash: "00".repeat(28),
    // Core wiring. tx3 hashes the exact bytes it is handed, so the vendored
    // e2e scripts (single-CBOR) are stripped to their flat program here; the
    // hashes above are MeshJS ledger hashes of that flat program.
    node_policy: core.registryNodeCs,
    node_policy_script: unwrapCborBytes(core.registry.code),
    plb_script: unwrapCborBytes(core.programmableLogicBase.code),
    protocol_params_ref: "00#0",
    principal_name: PRINCIPAL,
    reference_name: REFERENCE,
    plb_global_script_ref: "00#0",
    plb_global_script_address: "00",
    core_transfer_script_ref: "00#0",
    core_transfer_script_address: "00",
    core_third_party_script_ref: "00#0",
    core_third_party_script_address: "00",
    core_issuance_script_ref: "00#0",
    core_issuance_script_address: "00",
    cbor_hex_policy: core.cborHexCs,
    cbor_hex_script: unwrapCborBytes(core.issuanceCborHexMint.code),
    cbor_hex_ref: cborHexRef,
    upgrade_multisig_policy: core.upgradeMultisigHash,
    upgrade_multisig_script: unwrapCborBytes(core.upgradeMultisig.code),
    upgrade_multisig_script_ref: upgradeMultisigScriptRef,
    upgrade_multisig_stake_address: rewardAddrHex(core.upgradeMultisigHash),
    params_policy: core.paramsPolicy,
    params_script: unwrapCborBytes(core.protocolParams.code),
  };
}

/** Shared core env, completed with the published reference-script UTxOs. */
function coreEnv(): Record<string, unknown> {
  return {
    ...bootstrapEnv(),
    protocol_params_ref: paramsRef,
    plb_global_script_ref: coreRefs.plbGlobal,
    plb_global_script_address: rewardAddrHex(core.programmableLogicGlobalHash),
    core_transfer_script_ref: coreRefs.coreTransfer,
    core_transfer_script_address: rewardAddrHex(core.transferHash),
    core_third_party_script_ref: coreRefs.coreThirdParty,
    core_third_party_script_address: rewardAddrHex(core.thirdPartyHash),
    core_issuance_script_ref: coreRefs.coreIssuance,
    core_issuance_script_address: rewardAddrHex(core.issuanceLogicHash),
  };
}

beforeAll(async () => {
  devnet = await TrixDevnet.start({ protocolRoot: "event-triggered-assets" });

  registrar = devnet.wallet("bootstrap/registrar");
  registrant = devnet.wallet("bootstrap/registrant");
  await devnet.payTo(registrar.address, 60n * ADA);
  await devnet.payTo(registrant.address, 40n * ADA);

  // Dedicated one-shot wallets: tx3's coin selection must never touch a
  // reserved genesis UTxO.
  const registrySeedWallet = devnet.wallet("bootstrap/registry-seed");
  const cborSeedWallet = devnet.wallet("bootstrap/cbor-seed");
  const configSeedWallet = devnet.wallet("bootstrap/config-seed");
  const paramsSeedWallet = devnet.wallet("bootstrap/params-seed");
  for (const wallet of [
    registrySeedWallet,
    cborSeedWallet,
    configSeedWallet,
    paramsSeedWallet,
  ]) {
    await devnet.payTo(wallet.address, 15n * ADA);
    await devnet.payTo(wallet.address, 5n * ADA);
  }

  const registrySeed = await devnet.seedUtxo(registrySeedWallet);
  const cborSeed = await devnet.seedUtxo(cborSeedWallet);
  const configSeed = await devnet.seedUtxo(configSeedWallet);
  const paramsSeed = await devnet.seedUtxo(paramsSeedWallet);

  core = applyCoreScripts({
    networkId: 0,
    maxInlineDatumBytes: MAX_INLINE_DATUM_BYTES,
    alwaysFailNonce: ALWAYS_FAIL_NONCE,
    protocolParamsRef: refParts(paramsSeed.ref),
    registryRef: refParts(registrySeed.ref),
    cborHexRef: refParts(cborSeed.ref),
    upgradeConfigRef: refParts(configSeed.ref),
  });
  registryAddr = scriptAddr(core.registryNodeCs);

  // Register every core withdraw-0 credential before any reference-script
  // UTxO exists, so MeshJS's registration never spends one.
  for (const hash of [
    core.programmableLogicGlobalHash,
    core.transferHash,
    core.thirdPartyHash,
    core.issuanceLogicHash,
    core.upgradeMultisigHash,
  ]) {
    await devnet.registerScriptStakeCredential(registrant, hash);
  }

  const env = bootstrapEnv();

  // 1. Registry origin node.
  const originDatum: Record<string, unknown> = {
    key: new Uint8Array(0),
    next: bytes(SENTINEL_NEXT),
    minting_logic_script: emptyVKey,
    transfer_logic_script: emptyVKey,
    third_party_logic_script: emptyVKey,
    unfracking_logic_script: emptyVKey,
    global_state_cs: new Uint8Array(0),
  };
  await confirm(
    clientFor(registrySeedWallet)
      .coreInitRegistry({
        registry_ref: registrySeed.ref,
        node_address: registryAddr,
        node_datum: originDatum,
      } as unknown as Parameters<Client["coreInitRegistry"]>[0])
      .env(env),
  );
  const originNode = one(
    await devnet.utxosOf(registryAddr),
    "registry origin node",
  );
  registryNodes.push({ ref: originNode.ref, datum: originDatum });

  // 2. Issuance-template reference NFT, locked at the always-fail address.
  const template = issuanceTemplate(
    issuanceMintCompiledCode,
    "00".repeat(28),
    core.paramsPolicy,
  );
  await confirm(
    clientFor(cborSeedWallet)
      .coreInitCborHex({
        cbor_ref: cborSeed.ref,
        lock_address: scriptAddr(core.alwaysFailHash),
        cbor_datum: {
          prefix_cbor_hex: bytes(template.prefix),
          postfix_cbor_hex: bytes(template.postfix),
        },
      } as unknown as Parameters<Client["coreInitCborHex"]>[0])
      .env(env),
  );
  cborHexRef = one(
    await devnet.utxosOf(scriptAddr(core.alwaysFailHash)),
    "cbor template",
  ).ref;

  // 3. Upgrade-multisig config, signed by the parameters genesis signer.
  await confirm(
    clientFor(configSeedWallet)
      .coreInitUpgradeConfig({
        config_ref: configSeed.ref,
        config_address: scriptAddr(core.upgradeMultisigHash),
        config_datum: { key_hash: bytes(paramsSeedWallet.keyHash) },
      } as unknown as Parameters<Client["coreInitUpgradeConfig"]>[0])
      .env(env),
  );
  const configRef = one(
    await devnet.utxosOf(scriptAddr(core.upgradeMultisigHash)),
    "upgrade config",
  ).ref;

  // The upgrade-multisig withdraw-0 must run from a reference script: pallas
  // does not count an inline withdrawal witness as a needed script.
  upgradeMultisigScriptRef = await deployReferenceScript(
    unwrapCborBytes(core.upgradeMultisig.code),
  );

  // 4. Protocol parameters (the upgrade withdraw-0 authorises genesis).
  await confirm(
    clientFor(paramsSeedWallet)
      .coreInitProtocolParams({
        params_ref: paramsSeed.ref,
        config_ref: configRef,
        params_address: scriptAddr(core.paramsPolicy),
        params_datum: {
          programmable_logic_global_cred: {
            Script: { hash: bytes(core.programmableLogicGlobalHash) },
          },
          issuance_logic_cred: {
            Script: { hash: bytes(core.issuanceLogicHash) },
          },
          transfer_cred: { Script: { hash: bytes(core.transferHash) } },
          third_party_cred: { Script: { hash: bytes(core.thirdPartyHash) } },
          upgrade_cred: { Script: { hash: bytes(core.upgradeMultisigHash) } },
          pending_upgrade_cred: { None: {} },
        },
      } as unknown as Parameters<Client["coreInitProtocolParams"]>[0])
      .env(bootstrapEnv()),
  );
  paramsRef = one(
    await devnet.utxosOf(scriptAddr(core.paramsPolicy)),
    "protocol params",
  ).ref;

  // 5. Publish the core withdraw-0 scripts as reference scripts (flat form,
  // matching the hashes baked into the env).
  coreRefs = {
    plbGlobal: await deployReferenceScript(
      unwrapCborBytes(core.programmableLogicGlobal.code),
    ),
    coreTransfer: await deployReferenceScript(
      unwrapCborBytes(core.transfer.code),
    ),
    coreThirdParty: await deployReferenceScript(
      unwrapCborBytes(core.thirdParty.code),
    ),
    coreIssuance: await deployReferenceScript(
      unwrapCborBytes(core.issuanceLogic.code),
    ),
  };
}, 300_000);

afterAll(() => devnet.stop());

// -------------------------------------------------------------- instrument glue

interface InstrumentRefs {
  issuance: string;
  transfer: string;
  thirdParty: string;
  transformation: string;
}

interface Instrument {
  issuer: DevnetWallet;
  holder: DevnetWallet;
  bond: BondScripts;
  refs: InstrumentRefs;
  env: Record<string, unknown>;
  plbHash: string;
  nodeRef: string;
  principalRef: string;
  principalAddress: string;
  referenceRef: string;
  referenceAddress: string;
  schedule: { deadline: number; value: number }[];
  finalValue: number;
}

interface InstrumentOptions {
  issuer: DevnetWallet;
  holder: DevnetWallet;
  beneficiary: DevnetWallet;
}

/** Apply one bond's scripts, fund the actors, and atomically register + issue. */
async function setupInstrument(o: InstrumentOptions): Promise<Instrument> {
  const { issuer, holder } = o;

  for (const [wallet, topups] of [
    [issuer, [20, 10, 5]],
    [holder, [10, 5]],
  ] as [DevnetWallet, number[]][]) {
    for (const ada of topups) {
      await devnet.payTo(wallet.address, BigInt(ada) * ADA);
    }
  }

  // The schedule is baked into every module script, so it is fixed before
  // funding/registration/publishing. The lead leaves room for that setup to
  // complete before the first deadline (and before d4, the transform's gate).
  const scheduleStart = (await devnet.tip()).timeMs + 120_000;
  const schedule = [
    { deadline: scheduleStart + 10_000, value: 1040 },
    { deadline: scheduleStart + 20_000, value: 1081 },
    { deadline: scheduleStart + 30_000, value: 1124 },
    { deadline: scheduleStart + 40_000, value: 1169 },
  ];
  const finalValue = schedule[schedule.length - 1].value;

  const bond = bondScripts({
    registryNodeCs: core.registryNodeCs,
    paramsPolicy: core.paramsPolicy,
    issuer: { kind: "key", hash: issuer.keyHash },
    principalName: PRINCIPAL,
    referenceName: REFERENCE,
    schedule,
    scale: SCALE,
  });

  // Register this bond's withdraw-0 credentials, then publish its scripts.
  for (const script of [
    bond.issuance,
    bond.transfer,
    bond.thirdParty,
    bond.transformation,
  ]) {
    await devnet.registerScriptStakeCredential(
      registrant,
      scriptHashOf(script),
    );
  }
  const refs: InstrumentRefs = {
    issuance: await deployReferenceScript(unwrapCborBytes(bond.issuance.code)),
    transfer: await deployReferenceScript(unwrapCborBytes(bond.transfer.code)),
    thirdParty: await deployReferenceScript(
      unwrapCborBytes(bond.thirdParty.code),
    ),
    transformation: await deployReferenceScript(
      unwrapCborBytes(bond.transformation.code),
    ),
  };

  const env: Record<string, unknown> = {
    ...coreEnv(),
    cip_policy: bond.cipPolicy,
    cip_policy_script: unwrapCborBytes(bond.issuanceMint.code),
    native_policy: bond.nativePolicy,
    native_mint_script: unwrapCborBytes(bond.nativeMint.code),
    issuance_script_ref: refs.issuance,
    issuance_script_address: rewardAddrHex(scriptHashOf(bond.issuance)),
    transfer_logic_script_ref: refs.transfer,
    transfer_logic_script_address: rewardAddrHex(scriptHashOf(bond.transfer)),
    third_party_logic_script_ref: refs.thirdParty,
    third_party_logic_script_address: rewardAddrHex(
      scriptHashOf(bond.thirdParty),
    ),
    transformation_script_ref: refs.transformation,
    transformation_script_address: rewardAddrHex(
      scriptHashOf(bond.transformation),
    ),
    issuance_hash: scriptHashOf(bond.issuance),
    reference_name: REFERENCE,
  };

  // Registry linked list: cover the greatest key below the new policy.
  const covering = registryNodes
    .filter((n) => hexOf(n.datum.key as Uint8Array) < bond.cipPolicy)
    .sort((a, b) =>
      hexOf(a.datum.key as Uint8Array) < hexOf(b.datum.key as Uint8Array)
        ? -1
        : 1,
    )
    .at(-1);
  if (!covering) throw new Error("no covering registry node available");

  const coveringDatum = { ...covering.datum, next: bytes(bond.cipPolicy) };
  const nodeDatum: Record<string, unknown> = {
    key: bytes(bond.cipPolicy),
    next: covering.datum.next,
    minting_logic_script: {
      Script: { hash: bytes(scriptHashOf(bond.issuance)) },
    },
    transfer_logic_script: {
      Script: { hash: bytes(scriptHashOf(bond.transfer)) },
    },
    third_party_logic_script: {
      Script: { hash: bytes(scriptHashOf(bond.thirdParty)) },
    },
    unfracking_logic_script: emptyVKey,
    global_state_cs: new Uint8Array(0),
  };

  const plbHash = core.programmableLogicBaseCred.hash;
  const beneficiaryAddress = plbAddr(plbHash, o.beneficiary.keyHash, false);
  const referenceAddress = plbAddr(
    plbHash,
    scriptHashOf(bond.transformation),
    true,
  );

  const registerRefs = sortRefs([
    paramsRef,
    cborHexRef,
    refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const paramsIdx = refIndexOf(registerRefs, paramsRef);

  const beforePrincipal = await snapshot(beneficiaryAddress);
  const beforeReference = await snapshot(referenceAddress);

  const registerHash = await confirm(
    clientFor(issuer)
      .registerIssue({
        quantity: Number(QUANTITY),
        node_datum: nodeDatum,
        reference_datum: referenceDatum(bond, schedule, SCALE),
        beneficiary_address: beneficiaryAddress,
        reference_address: referenceAddress,
        covering_ref: covering.ref,
        covering_address: registryAddr,
        covering_datum: coveringDatum,
        params_idx: paramsIdx,
        new_node_ix: 1,
      } as unknown as Parameters<Client["registerIssue"]>[0])
      .env(env),
  );

  // The template emits the covering continuation first and the new node
  // second (the same layout `new_node_ix` names).
  const coveringAfterRef = `${registerHash}#0`;
  const newNodeRef = `${registerHash}#1`;
  const principal = one(
    await addedSince(beneficiaryAddress, beforePrincipal),
    "principal",
  );
  const referenceToken = one(
    await addedSince(referenceAddress, beforeReference),
    "reference token",
  );

  covering.ref = coveringAfterRef;
  covering.datum = coveringDatum;
  registryNodes.push({ ref: newNodeRef, datum: nodeDatum });

  return {
    issuer,
    holder,
    bond,
    refs,
    env,
    plbHash,
    nodeRef: newNodeRef,
    principalRef: principal.ref,
    principalAddress: beneficiaryAddress,
    referenceRef: referenceToken.ref,
    referenceAddress,
    schedule,
    finalValue,
  };
}

function referenceDatum(
  bond: BondScripts,
  schedule: { deadline: number; value: number }[],
  value: number,
): Record<string, unknown> {
  return {
    metadata: new Uint8Array(0),
    version: 1,
    extra: {
      schedule: schedule.map((s) => ({ deadline: s.deadline, value: s.value })),
      value,
      native_policy: bytes(bond.nativePolicy),
    },
  };
}

function lookup(
  schedule: { deadline: number; value: number }[],
  now: number,
): number {
  return schedule.reduce((v, s) => (s.deadline <= now ? s.value : v), 0);
}

// ------------------------------------------------------------------- owner path

test("registers, transfers, transforms, and graduates on the owner path", async () => {
  const issuer = devnet.wallet("owner/issuer");
  const holder = devnet.wallet("owner/holder");
  const inst = await setupInstrument({
    issuer,
    holder,
    beneficiary: issuer,
  });
  const { bond } = inst;

  // ---- transfer (T2, owner path) ---------------------------------------
  const holderAddress = plbAddr(inst.plbHash, holder.keyHash, false);
  const transferRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    coreRefs.plbGlobal,
    coreRefs.coreTransfer,
    inst.refs.transfer,
  ]);
  const transferWdrls = [
    core.programmableLogicGlobalHash,
    core.transferHash,
    scriptHashOf(bond.transfer),
  ];
  const beforeHolder = await snapshot(holderAddress);
  await confirm(
    clientFor(issuer)
      .transfer({
        token_address: inst.principalAddress,
        token_ref: inst.principalRef,
        params_idx: refIndexOf(transferRefs, paramsRef),
        wdrl_idx: withdrawalIndexOf(
          transferWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_idx: refIndexOf(transferRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
        recipient_address: holderAddress,
      } as unknown as Parameters<Client["transfer"]>[0])
      .env(inst.env),
  );
  const holderPrincipal = one(
    await addedSince(holderAddress, beforeHolder),
    "holder principal",
  );

  // ---- transform (T3) ---------------------------------------------------
  await devnet.waitForChainTimeMs(inst.schedule[0].deadline + 1_000);
  const tip = await devnet.tip();
  const transformRefs = sortRefs([...transferRefs, inst.refs.transformation]);
  const transformWdrls = [...transferWdrls, scriptHashOf(bond.transformation)];
  const beforeTransformReference = await snapshot(inst.referenceAddress);
  await confirm(
    clientFor(issuer)
      .transform({
        reference_ref: inst.referenceRef,
        reference_address: inst.referenceAddress,
        params_idx: refIndexOf(transformRefs, paramsRef),
        wdrl_idx: withdrawalIndexOf(
          transformWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_idx: refIndexOf(transformRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
        reference_datum: referenceDatum(
          bond,
          inst.schedule,
          lookup(inst.schedule, tip.timeMs),
        ),
        since_slot: tip.slot,
      } as unknown as Parameters<Client["transform"]>[0])
      .env(inst.env),
  );
  // The transformation rewrites the reference token in place: track the
  // continuation, which graduation must reference.
  const transformedReference = one(
    await addedSince(inst.referenceAddress, beforeTransformReference),
    "reference token continuation",
  );

  // ---- graduate (T4, owner path) ---------------------------------------
  await devnet.waitForChainTimeMs(
    inst.schedule[inst.schedule.length - 1].deadline + 1_000,
    300,
  );
  const tip4 = await devnet.tip();
  const graduateRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    transformedReference.ref,
    coreRefs.plbGlobal,
    coreRefs.coreTransfer,
    inst.refs.transfer,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const graduateWdrls = [
    core.programmableLogicGlobalHash,
    core.transferHash,
    scriptHashOf(bond.transfer),
    scriptHashOf(bond.issuance),
    core.issuanceLogicHash,
  ];
  const nativeQuantity = Number(
    (QUANTITY * BigInt(inst.finalValue)) / BigInt(SCALE),
  );
  const payoutAddress = baseAddr(holder.keyHash, holder.keyHash);

  await confirm(
    clientFor(holder)
      .graduateOwner({
        token_address: holderAddress,
        token_ref: holderPrincipal.ref,
        params_idx: refIndexOf(graduateRefs, paramsRef),
        wdrl_idx: withdrawalIndexOf(
          graduateWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_idx: refIndexOf(graduateRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
        reference_ref: transformedReference.ref,
        quantity: Number(QUANTITY),
        native_quantity: nativeQuantity,
        payout_address: payoutAddress,
        since_slot: tip4.slot,
      } as unknown as Parameters<Client["graduateOwner"]>[0])
      .env(inst.env),
  );

  const nativeHeld =
    (await devnet.assetsOf(payoutAddress))[bond.nativePolicy + PRINCIPAL] ?? 0n;
  expect(nativeHeld).toBe(BigInt(nativeQuantity));
  const principalHeld =
    (await devnet.assetsOf(holderAddress))[bond.cipPolicy + PRINCIPAL] ?? 0n;
  expect(principalHeld).toBe(0n);
}, 300_000);

// ------------------------------------------------------------- third-party path

test("graduates through the permissionless third-party path", async () => {
  const issuer = devnet.wallet("third/issuer");
  const holder = devnet.wallet("third/holder");
  const payout = devnet.wallet("third/payout");
  const submitter = devnet.wallet("third/submitter");
  await devnet.payTo(submitter.address, 10n * ADA);
  await devnet.payTo(submitter.address, 5n * ADA);

  const inst = await setupInstrument({
    issuer,
    holder,
    beneficiary: holder,
  });
  const { bond } = inst;
  const holderAddress = plbAddr(inst.plbHash, holder.keyHash, false);

  // ---- register payout key (T2b) ---------------------------------------
  const payoutKeyWdrls = [
    core.programmableLogicGlobalHash,
    core.transferHash,
    scriptHashOf(bond.transfer),
  ];
  const payoutRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    coreRefs.plbGlobal,
    coreRefs.coreTransfer,
    inst.refs.transfer,
  ]);
  const beforeHolder = await snapshot(holderAddress);
  await confirm(
    clientFor(holder)
      .registerPayoutKey({
        token_address: holderAddress,
        token_ref: inst.principalRef,
        params_idx: refIndexOf(payoutRefs, paramsRef),
        wdrl_idx: withdrawalIndexOf(
          payoutKeyWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_idx: refIndexOf(payoutRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
        payout_credential: { Key: { hash: bytes(payout.keyHash) } },
      } as unknown as Parameters<Client["registerPayoutKey"]>[0])
      .env(inst.env),
  );
  const committed = one(
    await addedSince(holderAddress, beforeHolder),
    "committed principal",
  );

  // ---- graduate (T4, third-party path) ---------------------------------
  await devnet.waitForChainTimeMs(
    inst.schedule[inst.schedule.length - 1].deadline + 1_000,
    300,
  );
  const tip = await devnet.tip();
  const graduateRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    inst.referenceRef,
    coreRefs.plbGlobal,
    coreRefs.coreThirdParty,
    inst.refs.thirdParty,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const graduateWdrls = [
    core.programmableLogicGlobalHash,
    core.thirdPartyHash,
    scriptHashOf(bond.thirdParty),
    scriptHashOf(bond.issuance),
    core.issuanceLogicHash,
  ];
  const nativeQuantity = Number(
    (QUANTITY * BigInt(inst.finalValue)) / BigInt(SCALE),
  );
  const payoutAddress = baseAddr(payout.keyHash, holder.keyHash);

  await confirm(
    clientFor(submitter)
      .graduateThirdParty({
        token_address: holderAddress,
        token_ref: committed.ref,
        params_idx: refIndexOf(graduateRefs, paramsRef),
        wdrl_idx: withdrawalIndexOf(
          graduateWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_idx: refIndexOf(graduateRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
        outputs_start_idx: 1,
        reference_ref: inst.referenceRef,
        quantity: Number(QUANTITY),
        native_quantity: nativeQuantity,
        payout_address: payoutAddress,
        since_slot: tip.slot,
      } as unknown as Parameters<Client["graduateThirdParty"]>[0])
      .env(inst.env),
  );

  const nativeHeld =
    (await devnet.assetsOf(payoutAddress))[bond.nativePolicy + PRINCIPAL] ?? 0n;
  expect(nativeHeld).toBe(BigInt(nativeQuantity));
  // The ghost continuation stays at the owner's PLB address.
  expect((await devnet.utxosOf(holderAddress)).length).toBe(1);
}, 300_000);

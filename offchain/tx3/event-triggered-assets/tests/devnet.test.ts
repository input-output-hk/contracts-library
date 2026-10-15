/**
 * Real-world happy paths for the tokenized bond over the vendored CIP-113 core
 * (cardano-foundation/cip113-programmable-tokens): deploy the core through the
 * tx3 test kit, create the vault, register the instrument, then drive the
 * deposit -> claim -> redeem -> graduate lifecycle on both the owner path
 * (transfer / owner-signed claim and graduation) and the issuer path
 * (opt-in `commit` / issuer-triggered claim and graduation) against a trix
 * devnet.
 *
 * Single-signer discipline: the tx signer must be the credential the protocol
 * requires, so each step rebinds the generated client's `Signer` party.
 */

import { afterAll, beforeAll, expect, test } from "vitest";
import { type TxBuilder } from "tx3-sdk";

import { couponName, stepName, type Bond } from "@contracts-library/meshjs";

import {
  DEVNET_POLL,
  TrixDevnet,
  unwrapCborBytes,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import { Client } from "../codegen/ts-client/tokenized-bond/protocol";
import {
  type CoreScripts,
  applyCoreScripts,
  bondScripts,
  bytes,
  hexOf,
  issuanceMintCompiledCode,
  issuanceTemplate,
  payoutArgs,
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

const PRINCIPAL = 1000;
const INTERVAL = 10_000;
const AMOUNTS = [1040];
const VAULT_NFT_NAME = "5630"; // "V0"
const VAULT_ADA = 5n * ADA;
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
    issuance_script_ref: "00#0",
    issuance_script_address: "00",
    transfer_logic_script_ref: "00#0",
    transfer_logic_script_address: "00",
    third_party_logic_script_ref: "00#0",
    third_party_logic_script_address: "00",
    issuance_hash: "00".repeat(28),
    coupon_policy: "00".repeat(28),
    coupon_script: "00",
    vault_script: "00",
    vault_nft_policy: "00".repeat(28),
    vault_nft_script: "00",
    vault_nft_name: "00",
    vault_principal: 0,
    // Core wiring. tx3 hashes the exact bytes it is handed, so the vendored
    // e2e scripts (single-CBOR) are stripped to their flat program here; the
    // hashes above are MeshJS ledger hashes of that flat program.
    node_policy: core.registryNodeCs,
    node_policy_script: unwrapCborBytes(core.registry.code),
    plb_script: unwrapCborBytes(core.programmableLogicBase.code),
    protocol_params_ref: "00#0",
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
}

interface Instrument {
  issuer: DevnetWallet;
  bond: Bond;
  refs: InstrumentRefs;
  env: Record<string, unknown>;
  plbHash: string;
  nodeRef: string;
  vaultRef: string;
  vaultAddress: string;
}

interface InstrumentOptions {
  issuer: DevnetWallet;
  holder: DevnetWallet;
}

/** Apply one bond, publish its scripts, create its vault and register it. */
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

  const bond = bondScripts({
    registryNodeCs: core.registryNodeCs,
    paramsPolicy: core.paramsPolicy,
    issuer: { kind: "key", hash: issuer.keyHash },
    vaultNftName: VAULT_NFT_NAME,
    principal: PRINCIPAL,
    interval: INTERVAL,
    amounts: AMOUNTS,
  });

  // Register this bond's withdraw-0 credentials, then publish its scripts.
  for (const script of bond.withdrawCredentials) {
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
  };

  const env: Record<string, unknown> = {
    ...coreEnv(),
    cip_policy: bond.cipPolicy,
    cip_policy_script: unwrapCborBytes(bond.issuanceMint.code),
    issuance_script_ref: refs.issuance,
    issuance_script_address: rewardAddrHex(scriptHashOf(bond.issuance)),
    transfer_logic_script_ref: refs.transfer,
    transfer_logic_script_address: rewardAddrHex(scriptHashOf(bond.transfer)),
    third_party_logic_script_ref: refs.thirdParty,
    third_party_logic_script_address: rewardAddrHex(
      scriptHashOf(bond.thirdParty),
    ),
    issuance_hash: scriptHashOf(bond.issuance),
    coupon_policy: bond.cntPolicy,
    coupon_script: unwrapCborBytes(bond.couponPolicy.code),
    vault_script: unwrapCborBytes(bond.vault.code),
    vault_nft_policy: bond.vaultNftCs,
    vault_nft_script: unwrapCborBytes(bond.vaultNft.code),
    vault_nft_name: VAULT_NFT_NAME,
    vault_principal: PRINCIPAL,
  };

  // ---- create the vault (§3.1) ------------------------------------------
  const vaultAddress = scriptAddr(bond.vaultHash);
  const beforeVault = await snapshot(vaultAddress);
  await confirm(
    clientFor(issuer)
      .createVault({
        vault_address: vaultAddress,
        vault_ada: Number(VAULT_ADA),
      } as unknown as Parameters<Client["createVault"]>[0])
      .env(env),
  );
  const vault = one(await addedSince(vaultAddress, beforeVault), "vault");

  // ---- register (§4.1) ----------------------------------------------------
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

  const registerHash = await confirm(
    clientFor(issuer)
      .register({
        node_datum: nodeDatum,
        covering_ref: covering.ref,
        covering_address: registryAddr,
        covering_datum: coveringDatum,
      } as unknown as Parameters<Client["register"]>[0])
      .env(env),
  );

  // The template emits the covering continuation first and the new node second.
  const newNodeRef = `${registerHash}#1`;
  covering.ref = `${registerHash}#0`;
  covering.datum = coveringDatum;
  registryNodes.push({ ref: newNodeRef, datum: nodeDatum });

  return {
    issuer,
    bond,
    refs,
    env,
    plbHash: core.programmableLogicBaseCred.hash,
    nodeRef: newNodeRef,
    vaultRef: vault.ref,
    vaultAddress,
  };
}

// ------------------------------------------------------------------- owner path

test("deposits, transfers, claims, redeems and graduates on the owner path", async () => {
  const issuer = devnet.wallet("holder/issuer");
  const holder = devnet.wallet("holder/holder");
  const couponOwner = devnet.wallet("holder/coupon");
  const inst = await setupInstrument({ issuer, holder });
  const { bond } = inst;
  for (const ada of [10, 5]) {
    await devnet.payTo(couponOwner.address, BigInt(ada) * ADA);
  }

  // ---- deposit (§4.2): the issuer deposits; the certificate starts at the
  // issuer's PLB-custodied address ----------------------------------------
  const tip0 = await devnet.tip();
  const untilSlot = tip0.slot + 30;
  const start = devnet.slotTimeMs(untilSlot);
  const depositorAddress = plbAddr(inst.plbHash, issuer.keyHash, false);
  const depositRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const beforeDeposit = await snapshot(depositorAddress);
  await confirm(
    clientFor(issuer)
      .deposit({
        vault_address: inst.vaultAddress,
        vault_ref: inst.vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        certificate_address: depositorAddress,
        step_name: bytes(stepName(0)),
        start,
        until_slot: untilSlot,
        params_idx: refIndexOf(depositRefs, paramsRef),
        node_idx: refIndexOf(depositRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
      } as unknown as Parameters<Client["deposit"]>[0])
      .env(inst.env),
  );
  // The instrument has exactly one vault UTxO: take it from its address.
  let vaultRef = one(await devnet.utxosOf(inst.vaultAddress), "vault").ref;
  const certificate = one(
    await addedSince(depositorAddress, beforeDeposit),
    "certificate",
  );
  expect(
    (await devnet.assetsOf(depositorAddress))[bond.cipPolicy + stepName(0)],
  ).toBe(1n);
  expect((await devnet.lovelaceBalanceOf(inst.vaultAddress)).lovelace).toBe(
    VAULT_ADA + BigInt(PRINCIPAL),
  );

  // ---- transfer (§4.3): owner change clears `commit` ----------------------
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
        certificate_address: depositorAddress,
        certificate_ref: certificate.ref,
        recipient_address: holderAddress,
        certificate_datum: {
          start,
          commit: { None: {} },
          cnt_policy: bytes(bond.cntPolicy),
        },
        params_idx: refIndexOf(transferRefs, paramsRef),
        node_idx: refIndexOf(transferRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          transferWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
      } as unknown as Parameters<Client["transfer"]>[0])
      .env(inst.env),
  );
  const heldCertificate = one(
    await addedSince(holderAddress, beforeHolder),
    "moved certificate",
  );
  expect(
    (await devnet.assetsOf(depositorAddress))[bond.cipPolicy + stepName(0)],
  ).toBeUndefined();

  // ---- claim the coupon, step 1 (§4.5) ------------------------------------
  const deadline = start + INTERVAL;
  await devnet.waitForChainTimeMs(deadline + 1_000, 120);
  const tip1 = await devnet.tip();
  const claimRefs = sortRefs([
    ...transferRefs,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const claimWdrls = [
    ...transferWdrls,
    scriptHashOf(bond.issuance),
    core.issuanceLogicHash,
  ];
  const beforeAdvance = await snapshot(holderAddress);
  const beforeCoupon = await snapshot(couponOwner.address);
  await confirm(
    clientFor(holder)
      .claimOwner({
        certificate_address: holderAddress,
        certificate_ref: heldCertificate.ref,
        old_name: bytes(stepName(0)),
        new_name: bytes(stepName(1)),
        coupon_name: bytes(couponName(AMOUNTS[0])),
        coupon_address: couponOwner.address,
        params_idx: refIndexOf(claimRefs, paramsRef),
        node_idx: refIndexOf(claimRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          claimWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
        since_slot: tip1.slot,
      } as unknown as Parameters<Client["claimOwner"]>[0])
      .env(inst.env),
  );
  const advancedCertificate = one(
    await addedSince(holderAddress, beforeAdvance),
    "advanced certificate",
  );
  const coupon = one(
    await addedSince(couponOwner.address, beforeCoupon),
    "coupon",
  );
  expect(
    (await devnet.assetsOf(holderAddress))[bond.cipPolicy + stepName(1)],
  ).toBe(1n);
  expect(
    (await devnet.assetsOf(couponOwner.address))[
      bond.cntPolicy + couponName(AMOUNTS[0])
    ],
  ).toBe(1n);

  // ---- redeem the coupon (§4.6) -------------------------------------------
  await confirm(
    clientFor(couponOwner)
      .redeem({
        coupon_ref: coupon.ref,
        coupon_name: bytes(couponName(AMOUNTS[0])),
        coupon_quantity: 1,
        vault_address: inst.vaultAddress,
        vault_ref: vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        ...payoutArgs(holder.address),
        payout_amount: AMOUNTS[0],
        payout_lovelace: Number(2n * ADA),
      } as unknown as Parameters<Client["redeem"]>[0])
      .env(inst.env),
  );
  vaultRef = one(await devnet.utxosOf(inst.vaultAddress), "vault").ref;
  expect((await devnet.lovelaceBalanceOf(inst.vaultAddress)).lovelace).toBe(
    VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]),
  );

  // ---- graduate (§4.7, owner path) ----------------------------------------
  const tip2 = await devnet.tip();
  const beforePrincipal = await snapshot(couponOwner.address);
  await confirm(
    clientFor(holder)
      .graduateOwner({
        certificate_address: holderAddress,
        certificate_ref: advancedCertificate.ref,
        final_name: bytes(stepName(1)),
        principal_coupon_name: bytes(couponName(PRINCIPAL)),
        coupon_address: couponOwner.address,
        params_idx: refIndexOf(claimRefs, paramsRef),
        node_idx: refIndexOf(claimRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          claimWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
        since_slot: tip2.slot,
      } as unknown as Parameters<Client["graduateOwner"]>[0])
      .env(inst.env),
  );
  expect((await devnet.utxosOf(holderAddress)).length).toBe(0);
  const principalCoupon = one(
    await addedSince(couponOwner.address, beforePrincipal),
    "principal coupon",
  );
  expect(
    (await devnet.assetsOf(couponOwner.address))[
      bond.cntPolicy + couponName(PRINCIPAL)
    ],
  ).toBe(1n);

  // ---- redeem the principal (§4.6) ----------------------------------------
  await confirm(
    clientFor(couponOwner)
      .redeem({
        coupon_ref: principalCoupon.ref,
        coupon_name: bytes(couponName(PRINCIPAL)),
        coupon_quantity: 1,
        vault_address: inst.vaultAddress,
        vault_ref: vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        ...payoutArgs(holder.address),
        payout_amount: PRINCIPAL,
        payout_lovelace: Number(2n * ADA),
      } as unknown as Parameters<Client["redeem"]>[0])
      .env(inst.env),
  );
  expect((await devnet.lovelaceBalanceOf(inst.vaultAddress)).lovelace).toBe(
    VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]) - BigInt(PRINCIPAL),
  );
}, 300_000);

// ------------------------------------------------------------------ issuer path

test("triggers claims and retirement on the issuer path", async () => {
  const issuer = devnet.wallet("issuer/issuer");
  const holder = devnet.wallet("issuer/holder");
  const payout = devnet.wallet("issuer/payout");
  await devnet.payTo(payout.address, 10n * ADA);
  await devnet.payTo(payout.address, 5n * ADA);

  const inst = await setupInstrument({ issuer, holder });
  const { bond } = inst;

  // ---- deposit (§4.2): the holder deposits --------------------------------
  const tip0 = await devnet.tip();
  const untilSlot = tip0.slot + 30;
  const start = devnet.slotTimeMs(untilSlot);
  const holderAddress = plbAddr(inst.plbHash, holder.keyHash, false);
  const depositRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const beforeDeposit = await snapshot(holderAddress);
  await confirm(
    clientFor(holder)
      .deposit({
        vault_address: inst.vaultAddress,
        vault_ref: inst.vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        certificate_address: holderAddress,
        step_name: bytes(stepName(0)),
        start,
        until_slot: untilSlot,
        params_idx: refIndexOf(depositRefs, paramsRef),
        node_idx: refIndexOf(depositRefs, inst.nodeRef),
        node_ref: inst.nodeRef,
      } as unknown as Parameters<Client["deposit"]>[0])
      .env(inst.env),
  );
  // The instrument has exactly one vault UTxO: take it from its address.
  let vaultRef = one(await devnet.utxosOf(inst.vaultAddress), "vault").ref;
  const certificate = one(
    await addedSince(holderAddress, beforeDeposit),
    "certificate",
  );

  // ---- authorize (§4.4): commit the payout key ----------------------------
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
  const beforeCommitted = await snapshot(holderAddress);
  await confirm(
    clientFor(holder)
      .authorize({
        certificate_address: holderAddress,
        certificate_ref: certificate.ref,
        payout_credential: {
          Some: { credential: { Key: { hash: bytes(payout.keyHash) } } },
        },
        params_idx: refIndexOf(transferRefs, paramsRef),
        node_idx: refIndexOf(transferRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          transferWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
      } as unknown as Parameters<Client["authorize"]>[0])
      .env(inst.env),
  );
  const committed = one(
    await addedSince(holderAddress, beforeCommitted),
    "committed certificate",
  );

  // ---- claim_issuer (§4.5): the issuer triggers the advance ---------------
  const deadline = start + INTERVAL;
  await devnet.waitForChainTimeMs(deadline + 1_000, 120);
  const tip1 = await devnet.tip();
  const thirdPartyRefs = sortRefs([
    paramsRef,
    inst.nodeRef,
    coreRefs.plbGlobal,
    coreRefs.coreThirdParty,
    inst.refs.thirdParty,
  ]);
  const thirdPartyWdrls = [
    core.programmableLogicGlobalHash,
    core.thirdPartyHash,
    scriptHashOf(bond.thirdParty),
  ];
  const claimRefs = sortRefs([
    ...thirdPartyRefs,
    inst.refs.issuance,
    coreRefs.coreIssuance,
  ]);
  const claimWdrls = [
    ...thirdPartyWdrls,
    scriptHashOf(bond.issuance),
    core.issuanceLogicHash,
  ];
  const beforeTriggeredCoupon = await snapshot(payout.address);
  const beforeAdvance = await snapshot(holderAddress);
  await confirm(
    clientFor(issuer)
      .claimIssuer({
        certificate_address: holderAddress,
        certificate_ref: committed.ref,
        old_name: bytes(stepName(0)),
        new_name: bytes(stepName(1)),
        coupon_name: bytes(couponName(AMOUNTS[0])),
        pay_address: payout.address,
        params_idx: refIndexOf(claimRefs, paramsRef),
        node_idx: refIndexOf(claimRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          claimWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
        since_slot: tip1.slot,
      } as unknown as Parameters<Client["claimIssuer"]>[0])
      .env(inst.env),
  );
  const advancedCertificate = one(
    await addedSince(holderAddress, beforeAdvance),
    "advanced certificate",
  );
  const triggeredCoupon = one(
    await addedSince(payout.address, beforeTriggeredCoupon),
    "triggered coupon",
  );
  expect(
    (await devnet.assetsOf(payout.address))[
      bond.cntPolicy + couponName(AMOUNTS[0])
    ],
  ).toBe(1n);
  expect(
    (await devnet.assetsOf(holderAddress))[bond.cipPolicy + stepName(1)],
  ).toBe(1n);

  // ---- redeem the coupon (the committed payout wallet holds it) -----------
  await confirm(
    clientFor(payout)
      .redeem({
        coupon_ref: triggeredCoupon.ref,
        coupon_name: bytes(couponName(AMOUNTS[0])),
        coupon_quantity: 1,
        vault_address: inst.vaultAddress,
        vault_ref: vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        ...payoutArgs(holder.address),
        payout_amount: AMOUNTS[0],
        payout_lovelace: Number(2n * ADA),
      } as unknown as Parameters<Client["redeem"]>[0])
      .env(inst.env),
  );
  vaultRef = one(await devnet.utxosOf(inst.vaultAddress), "vault").ref;
  expect((await devnet.lovelaceBalanceOf(inst.vaultAddress)).lovelace).toBe(
    VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]),
  );

  // ---- graduate_issuer (§4.7): ghost shell + principal coupon -------------
  const tip2 = await devnet.tip();
  const beforeShell = await snapshot(holderAddress);
  const beforePrincipal = await snapshot(payout.address);
  await confirm(
    clientFor(issuer)
      .graduateIssuer({
        certificate_address: holderAddress,
        certificate_ref: advancedCertificate.ref,
        final_name: bytes(stepName(1)),
        principal_coupon_name: bytes(couponName(PRINCIPAL)),
        pay_address: payout.address,
        params_idx: refIndexOf(claimRefs, paramsRef),
        node_idx: refIndexOf(claimRefs, inst.nodeRef),
        wdrl_idx: withdrawalIndexOf(
          claimWdrls,
          core.programmableLogicGlobalHash,
        ),
        node_ref: inst.nodeRef,
        since_slot: tip2.slot,
      } as unknown as Parameters<Client["graduateIssuer"]>[0])
      .env(inst.env),
  );
  // The paired shell is the first output; it preserves the address and datum
  // and carries no certificate.
  const shell = one(await addedSince(holderAddress, beforeShell), "shell");
  expect(
    (await devnet.assetsOf(holderAddress))[bond.cipPolicy + stepName(1)],
  ).toBeUndefined();
  const principalCoupon = one(
    await addedSince(payout.address, beforePrincipal),
    "principal coupon",
  );
  expect(
    (await devnet.assetsOf(payout.address))[
      bond.cntPolicy + couponName(PRINCIPAL)
    ],
  ).toBe(1n);
  expect(shell.lovelace).toBe(2n * ADA);

  // ---- redeem the principal (§4.6) ----------------------------------------
  await confirm(
    clientFor(payout)
      .redeem({
        coupon_ref: principalCoupon.ref,
        coupon_name: bytes(couponName(PRINCIPAL)),
        coupon_quantity: 1,
        vault_address: inst.vaultAddress,
        vault_ref: vaultRef,
        vault_datum: { cnt_policy: bytes(bond.cntPolicy) },
        ...payoutArgs(holder.address),
        payout_amount: PRINCIPAL,
        payout_lovelace: Number(2n * ADA),
      } as unknown as Parameters<Client["redeem"]>[0])
      .env(inst.env),
  );
  expect((await devnet.lovelaceBalanceOf(inst.vaultAddress)).lovelace).toBe(
    VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]) - BigInt(PRINCIPAL),
  );
}, 300_000);

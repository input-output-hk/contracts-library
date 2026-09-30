/**
 * Deploys the CIP-113 core on a devnet (test bootstrap), in the documented
 * dependency order. Uses funded wallet UTxOs as the one-shot genesis refs and
 * the real `upgrade_multisig` (config NFT + approval tree) as the upgrade
 * authority.
 */

import { mConStr0, type Asset, type UTxO } from "@meshsdk/core";

import { registryNodeToData } from "@contracts-library/meshjs";

import {
  collateralOf,
  makeProvider,
  newTxBuilder,
  signAndSubmit,
  waitForTx,
  type Account,
} from "../devnet";
import { issuanceMintCompiledCode } from "./blueprint";
import { rewardAddressOf, scriptAddressOf, scriptHashOf } from "./core";
import {
  issuanceCborHexToData,
  multisigSignature,
  multisigToData,
  protocolParamsToData,
} from "./data";
import { applyCoreScripts, type CoreConfig, type CoreScripts } from "./scripts";
import { issuanceTemplate } from "./template";

type Provider = ReturnType<typeof makeProvider>;

const NETWORK_ID: 0 | 1 = 0;
const MIN_ADA = 2_000_000n;
const SENTINEL_NEXT = "ff".repeat(30);
const EMPTY_VKEY = { kind: "key" as const, hash: "" };

// Token names are hex (MeshJS `mint`/units take hex asset names).
const ISSUANCE_CBOR_HEX_NAME = Buffer.from("IssuanceCborHex").toString("hex");
const PROTOCOL_PARAMS_NAME = Buffer.from("ProtocolParams").toString("hex");
const UPGRADE_MULTISIG_NAME = Buffer.from("UpgradeMultisig").toString("hex");

function lovelace(quantity: bigint = MIN_ADA): Asset {
  return { unit: "lovelace", quantity: quantity.toString() };
}

function asset(unit: string, quantity: string): Asset {
  return { unit, quantity };
}

function outRefKey(utxo: UTxO): string {
  return `${utxo.input.txHash}#${utxo.input.outputIndex}`;
}

export interface Deployment {
  config: CoreConfig;
  core: CoreScripts;
  refs: { protocolParams: UTxO; cborHex: UTxO; originNode: UTxO; upgradeConfig: UTxO };
  /** Funding UTxOs left to the payer after reserving the one-shot refs. */
  funding: UTxO[];
}

/**
 * Deploy the whole core. The payer must hold enough UTxOs: one dedicated
 * collateral, four one-shot genesis refs, and change (fund with >= 6 topups).
 */
export async function deployCore(
  provider: Provider,
  payer: Account,
): Promise<Deployment> {
  const collateral = await collateralOf(payer);
  const walletUtxos = await payer.wallet.getUtxos();
  const reserved = new Set<string>([outRefKey(collateral)]);

  const available = walletUtxos.filter((u) => !reserved.has(outRefKey(u)));
  const [paramsRef, registryRef, cborRef, configRef] = available;
  if (!paramsRef || !registryRef || !cborRef || !configRef) {
    throw new Error("deployCore: payer needs a collateral + 4 refs + change");
  }
  for (const ref of [paramsRef, registryRef, cborRef, configRef]) {
    reserved.add(outRefKey(ref));
  }
  const funding = walletUtxos.filter((u) => !reserved.has(outRefKey(u)));

  const config: CoreConfig = {
    networkId: NETWORK_ID,
    maxInlineDatumBytes: 1024,
    alwaysFailNonce: "ab".repeat(32),
    protocolParamsRef: { txHash: paramsRef.input.txHash, outputIndex: paramsRef.input.outputIndex },
    registryRef: { txHash: registryRef.input.txHash, outputIndex: registryRef.input.outputIndex },
    cborHexRef: { txHash: cborRef.input.txHash, outputIndex: cborRef.input.outputIndex },
    upgradeConfigRef: { txHash: configRef.input.txHash, outputIndex: configRef.input.outputIndex },
  };
  const core = applyCoreScripts(config);

  async function complete(builder: ReturnType<typeof newTxBuilder>): Promise<string> {
    const tx = await builder
      .txInCollateral(
        collateral.input.txHash,
        collateral.input.outputIndex,
        collateral.output.amount,
        collateral.output.address,
      )
      .changeAddress(payer.address)
      .selectUtxosFrom(funding)
      .complete();
    const hash = await signAndSubmit(payer, tx);
    await waitForTx(provider, hash);
    return hash;
  }

  async function registerScriptStake(code: string, hash: string): Promise<void> {
    await complete(
      newTxBuilder(provider)
        .registerStakeCertificate(rewardAddressOf(hash, NETWORK_ID))
        .certificateScript(code, "V3")
        .certificateRedeemerValue(mConStr0([])),
    );
  }

  // 1. Register every withdraw-0 credential (publish consent). The upgrade
  //    authority must be registered before protocol-params genesis uses it.
  for (const script of [
    core.programmableLogicGlobal,
    core.transfer,
    core.thirdParty,
    core.unfracking,
    core.issuanceLogic,
    core.upgradeMultisig,
  ]) {
    await registerScriptStake(script.code, scriptHashOf(script));
  }

  // 2. Registry origin node.
  await complete(
    newTxBuilder(provider)
      .txIn(registryRef.input.txHash, registryRef.input.outputIndex, registryRef.output.amount, registryRef.output.address)
      .mintPlutusScriptV3()
      .mint("1", core.registryNodeCs, "")
      .mintRedeemerValue(mConStr0([]))
      .mintingScript(core.registry.code)
      .txOut(scriptAddressOf(core.registryNodeCs, NETWORK_ID), [
        lovelace(),
        asset(core.registryNodeCs, "1"),
      ])
      .txOutInlineDatumValue(
        registryNodeToData({
          key: "",
          next: SENTINEL_NEXT,
          mintingLogic: EMPTY_VKEY,
          transferLogic: EMPTY_VKEY,
          thirdPartyLogic: EMPTY_VKEY,
          unfrackingLogic: EMPTY_VKEY,
          globalStateCs: "",
        }),
      ),
  );

  // 3. IssuanceCborHex template genesis (locked at the always-fail address).
  //    The template is invariant to the minting-logic hash value, so a
  //    placeholder split is valid for every bond under this deployment.
  const template = issuanceTemplate(issuanceMintCompiledCode, "00".repeat(28), core.paramsPolicy);
  await complete(
    newTxBuilder(provider)
      .txIn(cborRef.input.txHash, cborRef.input.outputIndex, cborRef.output.amount, cborRef.output.address)
      .mintPlutusScriptV3()
      .mint("1", core.cborHexCs, ISSUANCE_CBOR_HEX_NAME)
      .mintRedeemerValue(mConStr0([]))
      .mintingScript(core.issuanceCborHexMint.code)
      .txOut(scriptAddressOf(core.alwaysFailHash, NETWORK_ID), [
        lovelace(),
        asset(core.cborHexCs + ISSUANCE_CBOR_HEX_NAME, "1"),
      ])
      .txOutInlineDatumValue(issuanceCborHexToData(template.prefix, template.postfix)),
  );

  // 4. Upgrade-multisig config genesis: one-shot config NFT + approval tree
  //    held in a config UTxO at the upgrade authority's own address.
  await complete(
    newTxBuilder(provider)
      .txIn(configRef.input.txHash, configRef.input.outputIndex, configRef.output.amount, configRef.output.address)
      .mintPlutusScriptV3()
      .mint("1", core.upgradeMultisigHash, UPGRADE_MULTISIG_NAME)
      .mintRedeemerValue(mConStr0([]))
      .mintingScript(core.upgradeMultisig.code)
      .txOut(scriptAddressOf(core.upgradeMultisigHash, NETWORK_ID), [
        lovelace(),
        asset(core.upgradeMultisigHash + UPGRADE_MULTISIG_NAME, "1"),
      ])
      .txOutInlineDatumValue(
        multisigToData(multisigSignature(payer.keyHash)),
      ),
  );

  const upgradeConfig = await firstUtxoAt(provider, core.upgradeMultisigHash);

  // 5. Protocol-params genesis: the upgrade authority's withdraw-0 (satisfying
  //    its config tree) authorises the genesis; the config UTxO is referenced.
  await complete(
    newTxBuilder(provider)
      .txIn(paramsRef.input.txHash, paramsRef.input.outputIndex, paramsRef.output.amount, paramsRef.output.address)
      .readOnlyTxInReference(upgradeConfig.input.txHash, upgradeConfig.input.outputIndex)
      .mintPlutusScriptV3()
      .mint("1", core.paramsPolicy, PROTOCOL_PARAMS_NAME)
      .mintRedeemerValue(mConStr0([]))
      .mintingScript(core.protocolParams.code)
      .withdrawalPlutusScriptV3()
      .withdrawal(rewardAddressOf(core.upgradeMultisigHash, NETWORK_ID), "0")
      .withdrawalScript(core.upgradeMultisig.code)
      .withdrawalRedeemerValue(mConStr0([]))
      .txOut(scriptAddressOf(core.paramsPolicy, NETWORK_ID), [
        lovelace(),
        asset(core.paramsPolicy + PROTOCOL_PARAMS_NAME, "1"),
      ])
      .txOutInlineDatumValue(
        protocolParamsToData({
          programmableLogicGlobalCred: { kind: "script", hash: core.programmableLogicGlobalHash },
          issuanceLogicCred: { kind: "script", hash: core.issuanceLogicHash },
          transferCred: { kind: "script", hash: core.transferHash },
          thirdPartyCred: { kind: "script", hash: core.thirdPartyHash },
          upgradeCred: { kind: "script", hash: core.upgradeMultisigHash },
          pendingUpgradeCred: null,
        }),
      ),
  );

  const [protocolParams, cborHex, originNode] = await Promise.all([
    firstUtxoAt(provider, core.paramsPolicy),
    firstUtxoAt(provider, core.alwaysFailHash),
    firstUtxoAt(provider, core.registryNodeCs),
  ]);

  return {
    config,
    core,
    refs: { protocolParams, cborHex, originNode, upgradeConfig },
    funding,
  };
}

async function firstUtxoAt(provider: Provider, paymentHash: string): Promise<UTxO> {
  const address = scriptAddressOf(paymentHash, NETWORK_ID);
  for (let i = 0; i < 30; i++) {
    const utxos = await provider.fetchAddressUTxOs(address);
    if (utxos.length > 0) return utxos[utxos.length - 1];
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`no UTxO appeared at ${address}`);
}
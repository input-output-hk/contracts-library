/**
 * Builders for the `counter_*` demo validators (non-normative, see
 * `docs/upgradeability/`). They show a protocol's own builders on top of the
 * library's `addDelegateInvocation`:
 *
 *   - `buildCounterTickTx`  the opt-in V1/V2 native action (no registry read)
 *   - `buildForwardMintTx`  the forced genesis: mint a state token under the
 *                           forwarder's policy into a fresh counter
 *   - `buildForwardTx`      the forced forwarder spend + logic withdraw-0
 *   - `buildUpgradeTx`      the opt-in migration: V1 `Upgrade` + migration
 *                           withdraw-0 + owner consent + V2 output
 */

import {
  applyCborEncoding,
  applyParamsToScript,
  deserializeAddress,
  mConStr0,
  mConStr1,
  resolveScriptHash,
  serializePlutusScript,
  type Data,
  type MeshTxBuilder,
  type Network,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import type { ScriptAuthorizer } from "../../authorization";
import { opaqueRedeemer } from "../../upgradeability/datum";
import type { SettingsRefParams } from "../../upgradeability/types";
import { addDelegateInvocation } from "../../upgradeability/upgradeability";
import {
  counterDatumFromUtxo,
  counterDatumToData,
  tickRedeemer,
  upgradeRedeemer,
} from "./datum";
import {
  forwarderCompiledCode,
  logicCompiledCode,
  logicSteppedCompiledCode,
  migrationCompiledCode,
  plutusVersion,
  v1CompiledCode,
  v2CompiledCode,
} from "./blueprint";
import type { Credential, CounterDatum, MigrationParams } from "./types";

/**
 * Asset name (hex) of the counter's state token, `"counter"`. It is minted
 * under the forwarder's own policy, so the forced logic treats a counter as
 * genuine only if it carries exactly one unit of `(forwarder hash, name)`.
 */
export const STATE_TOKEN_NAME = Buffer.from("counter").toString("hex");

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

// ------------------------------------------------------------- script helpers

/** The script hash of a parameterized counter script (its payment credential). */
export function counterScriptHash(script: PlutusScript): string {
  return resolveScriptHash(script.code, script.version);
}

/** The bech32 address of a counter script (staking any). */
export function counterScriptAddress(
  script: PlutusScript,
  networkId = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

/**
 * Encode a bech32 address as the Aiken `Address` record a validator parameter
 * expects: `Constr 0 [payment_credential, stake_credential: Option]`, where a
 * credential is `Constr 0 [key_hash]` or `Constr 1 [script_hash]` and the
 * stake part is `Some(Inline(credential))` or `None`.
 */
export function addressToData(bech32: string): Data {
  const {
    pubKeyHash,
    scriptHash,
    stakeCredentialHash,
    stakeScriptCredentialHash,
  } = deserializeAddress(bech32);
  if (!pubKeyHash && !scriptHash) {
    throw new Error(`Cannot decode the payment credential of ${bech32}.`);
  }
  const payment: Data = scriptHash
    ? mConStr1([scriptHash])
    : mConStr0([pubKeyHash]);
  const stake: Data = stakeScriptCredentialHash
    ? mConStr0([mConStr1([stakeScriptCredentialHash])])
    : stakeCredentialHash
      ? mConStr0([mConStr0([stakeCredentialHash])])
      : mConStr1([]); // None
  return mConStr0([payment, stake]);
}

// ------------------------------------------------------------ script factories

/** The forced forwarder: holds state, forwards every spend to the registry's logic. */
export function counterForwarderScript(
  params: SettingsRefParams,
): PlutusScript {
  const code = applyParamsToScript(
    forwarderCompiledCode,
    [params.settingsPolicy, params.settingsTokenName],
    "Mesh",
  );
  return { code, version: plutusVersion };
}

/** The forced logic: a staking validator shared by every forwarder of one settings instance. */
export function counterLogicScript(params: SettingsRefParams): PlutusScript {
  const code = applyParamsToScript(
    logicCompiledCode,
    [params.settingsPolicy, params.settingsTokenName],
    "Mesh",
  );
  return { code, version: plutusVersion };
}

/** The forced logic after a schema upgrade: reads both counter shapes, writes `Stepped`. */
export function counterLogicSteppedScript(
  params: SettingsRefParams,
): PlutusScript {
  const code = applyParamsToScript(
    logicSteppedCompiledCode,
    [params.settingsPolicy, params.settingsTokenName],
    "Mesh",
  );
  return { code, version: plutusVersion };
}

/** The opt-in V1: native ticks plus the registry-delegated `Upgrade` path. */
export function counterV1Script(params: SettingsRefParams): PlutusScript {
  const code = applyParamsToScript(
    v1CompiledCode,
    [params.settingsPolicy, params.settingsTokenName],
    "Mesh",
  );
  return { code, version: plutusVersion };
}

/** The opt-in V2: a plain, native counter with no upgrade path (unparameterized). */
export function counterV2Script(): PlutusScript {
  return { code: applyCborEncoding(v2CompiledCode), version: plutusVersion };
}

/** The opt-in migration script: moves a V1 UTxO to the blessed V2 address. */
export function counterMigrationScript(params: MigrationParams): PlutusScript {
  const code = applyParamsToScript(
    migrationCompiledCode,
    [
      params.settingsPolicy,
      params.settingsTokenName,
      addressToData(params.v2Address),
    ],
    "Mesh",
  );
  return { code, version: plutusVersion };
}

// ------------------------------------------------------------------- builders

export interface TickTxParams {
  txBuilder: MeshTxBuilder;
  /** The V1 or V2 counter script (same native datum/redeemer shape). */
  script: PlutusScript;
  counterUtxo: UTxO;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * The native counter action: continuation at the same address with `count + 1`,
 * same owner, the input's value carried over, and the input tagged as
 * `prevInput` (the validators settle each UTxO by its own continuation).
 */
export async function buildCounterTickTx(p: TickTxParams): Promise<string> {
  const datum = counterDatumFromUtxo(p.counterUtxo);
  const continuation = counterDatumToData({
    count: datum.count + 1,
    owner: datum.owner,
    prevInput: {
      txHash: p.counterUtxo.input.txHash,
      outputIndex: p.counterUtxo.input.outputIndex,
    },
  });

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.counterUtxo.input.txHash,
      p.counterUtxo.input.outputIndex,
      p.counterUtxo.output.amount,
      p.counterUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(tickRedeemer())
    .txInScript(p.script.code)
    .txOut(p.counterUtxo.output.address, p.counterUtxo.output.amount)
    .txOutInlineDatumValue(continuation)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

export interface ForwardTxParams {
  txBuilder: MeshTxBuilder;
  forwarderScript: PlutusScript;
  /**
   * How to invoke the registered logic script: inline (`scriptCbor`) or by
   * reference (`reference`). Its hash is checked against the registry entry
   * before anything is wired.
   */
  logicAuthorizer: ScriptAuthorizer;
  forwarderUtxo: UTxO;
  /** The settings UTxO holding the registry (added as a reference input). */
  settingsUtxo: UTxO;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * The forced forwarder spend: requires the script currently registered for the
 * forwarder's own hash to run as a withdraw-0, and carries the state's
 * continuation (`count + 1`, tagged with the spent UTxO as `prevInput`) at the
 * forwarder address. Funds never move.
 *
 * Throws early if the forwarder is unregistered or the provided logic script
 * does not match the registry entry — a mistake surfaces as a clear error
 * instead of a rejected transaction.
 */
export async function buildForwardTx(p: ForwardTxParams): Promise<string> {
  const network = p.network ?? "preprod";

  const datum = counterDatumFromUtxo(p.forwarderUtxo);
  const continuation = counterDatumToData({
    count: datum.count + 1,
    owner: datum.owner,
    prevInput: {
      txHash: p.forwarderUtxo.input.txHash,
      outputIndex: p.forwarderUtxo.input.outputIndex,
    },
  });

  addDelegateInvocation({
    txBuilder: p.txBuilder,
    ownHash: counterScriptHash(p.forwarderScript),
    delegateAuthorizer: p.logicAuthorizer,
    settingsUtxo: p.settingsUtxo,
    network,
  });

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.forwarderUtxo.input.txHash,
      p.forwarderUtxo.input.outputIndex,
      p.forwarderUtxo.output.amount,
      p.forwarderUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(opaqueRedeemer())
    .txInScript(p.forwarderScript.code)
    .txOut(p.forwarderUtxo.output.address, p.forwarderUtxo.output.amount)
    .txOutInlineDatumValue(continuation)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

export interface ForwardMintTxParams {
  txBuilder: MeshTxBuilder;
  forwarderScript: PlutusScript;
  /** How to invoke the registered logic script (see `ForwardTxParams`). */
  logicAuthorizer: ScriptAuthorizer;
  /** The settings UTxO holding the registry (added as a reference input). */
  settingsUtxo: UTxO;
  /** Owner of the new counter (gates nothing in forced mode; kept in state). */
  owner: Credential;
  /** Lovelace locked with the new counter. */
  lovelace: bigint;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * The forced genesis: mint one state token under the forwarder's policy into a
 * fresh counter (`count: 0`, no `prevInput`) at the forwarder address. The
 * forwarder admits the mint once the registered logic runs, and the logic
 * accepts exactly this shape. Only counters created this way carry the token,
 * so a counter paid straight to the forwarder address is not genuine.
 *
 * Throws early if the forwarder is unregistered or the provided logic script
 * does not match the registry entry.
 */
export async function buildForwardMintTx(
  p: ForwardMintTxParams,
): Promise<string> {
  const networkId = networkIdOf(p.network ?? "preprod");
  const forwarderHash = counterScriptHash(p.forwarderScript);
  addDelegateInvocation({
    txBuilder: p.txBuilder,
    ownHash: forwarderHash,
    delegateAuthorizer: p.logicAuthorizer,
    settingsUtxo: p.settingsUtxo,
    network: p.network,
  });

  return await p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", forwarderHash, STATE_TOKEN_NAME)
    .mintingScript(p.forwarderScript.code)
    .mintRedeemerValue(opaqueRedeemer())
    .txOut(counterScriptAddress(p.forwarderScript, networkId), [
      { unit: "lovelace", quantity: p.lovelace.toString() },
      { unit: forwarderHash + STATE_TOKEN_NAME, quantity: "1" },
    ])
    .txOutInlineDatumValue(
      counterDatumToData({ count: 0, owner: p.owner, prevInput: null }),
    )
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

export interface UpgradeTxParams {
  txBuilder: MeshTxBuilder;
  v1Script: PlutusScript;
  /**
   * How to invoke the registered migration script: inline (`scriptCbor`) or by
   * reference (`reference`). Its hash is checked against the registry entry.
   */
  migrationAuthorizer: ScriptAuthorizer;
  v1Utxo: UTxO;
  /** The settings UTxO holding the registry (added as a reference input). */
  settingsUtxo: UTxO;
  /** Bech32 address of the V2 validator (the blessed migration target). */
  v2Address: string;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/**
 * The opt-in migration: spends the user's V1 UTxO with `Upgrade`, requires the
 * registered migration script as a withdraw-0, and re-creates the state at the
 * V2 address with `count` and `owner` preserved, tagged with the spent UTxO as
 * `prevInput`.
 *
 * Consent is enforced here — the owner's key must sign — so a governance
 * repoint of the migration script can never move funds without the owner.
 * Throws early on an unregistered V1, a mismatched migration script, or a
 * script-credential owner (not supported by the demo builders).
 */
export async function buildUpgradeTx(p: UpgradeTxParams): Promise<string> {
  const network = p.network ?? "preprod";

  const datum: CounterDatum = counterDatumFromUtxo(p.v1Utxo);
  if (datum.owner.kind !== "key") {
    throw new Error(
      "The demo upgrade builder requires the UTxO owner to be a key credential " +
        "(it signs to consent). Script owners need a custom builder.",
    );
  }
  p.txBuilder.requiredSignerHash(datum.owner.hash);

  addDelegateInvocation({
    txBuilder: p.txBuilder,
    ownHash: counterScriptHash(p.v1Script),
    delegateAuthorizer: p.migrationAuthorizer,
    settingsUtxo: p.settingsUtxo,
    network,
  });

  return await p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.v1Utxo.input.txHash,
      p.v1Utxo.input.outputIndex,
      p.v1Utxo.output.amount,
      p.v1Utxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(upgradeRedeemer())
    .txInScript(p.v1Script.code)
    .txOut(p.v2Address, p.v1Utxo.output.amount)
    .txOutInlineDatumValue(
      counterDatumToData({
        ...datum,
        prevInput: {
          txHash: p.v1Utxo.input.txHash,
          outputIndex: p.v1Utxo.input.outputIndex,
        },
      }),
    )
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

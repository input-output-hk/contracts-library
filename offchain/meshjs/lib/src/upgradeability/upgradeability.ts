/**
 * Transaction builders for the upgradeability building block (MeshJS).
 *
 * The registry lives in a settings UTxO (#20); changing it reuses the settings
 * builders (`buildRegistryProposeTx` / `buildRegistryApplyTx` below). What is
 * new here are the two mechanism builders:
 *
 *   - `buildCounterTickTx`  the opt-in V1/V2 native action (no registry read)
 *   - `buildForwardTx`      the forced forwarder spend + logic withdraw-0
 *   - `buildUpgradeTx`      the opt-in migration: V1 `Upgrade` + migration
 *                           withdraw-0 + owner consent + V2 output
 *
 * The `counter_*` validators are a non-normative demo (`docs/upgradeability/`):
 * a real protocol supplies its own state and its own logic / migration scripts,
 * reusing `applyAuthorization` for the withdraw-0 delegation the same way.
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

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import {
  buildApplyTx,
  buildProposeTx,
  type ApplyParams,
  type ProposeParams,
} from "../settings/settings";
import {
  counterDatumFromUtxo,
  counterDatumToData,
  opaqueRedeemer,
  registryFromUtxo,
  registryToData,
  tickRedeemer,
  upgradeRedeemer,
} from "./datum";
import {
  forwarderCompiledCode,
  logicCompiledCode,
  migrationCompiledCode,
  plutusVersion,
  v1CompiledCode,
  v2CompiledCode,
} from "./blueprint";
import type {
  CounterDatum,
  MigrationParams,
  Registry,
  SettingsRefParams,
} from "./types";

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

// ---------------------------------------------------------------- registry I/O

/**
 * Read the registry from the settings UTxO (inline datum). Throws if the value
 * is not a well-formed map of script hashes.
 */
export function readRegistry(settingsUtxo: UTxO): Registry {
  return registryFromUtxo(settingsUtxo);
}

/**
 * Propose a registry change: a settings `Propose` whose new value is the whole
 * registry map. Carry forward every entry you are not changing.
 */
export interface RegistryProposeParams extends Omit<ProposeParams, "newValue"> {
  registry: Registry;
}

export async function buildRegistryProposeTx(
  p: RegistryProposeParams,
): Promise<string> {
  return await buildProposeTx({ ...p, newValue: registryToData(p.registry) });
}

/**
 * Apply a matured registry proposal: exactly the settings `Apply` — the
 * registry is just the settings value, so nothing new is wired here.
 */
export async function buildRegistryApplyTx(p: ApplyParams): Promise<string> {
  return await buildApplyTx(p);
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
  const networkId = networkIdOf(network);

  if (p.logicAuthorizer.manual) {
    throw new Error(
      "`logicAuthorizer.manual` is not supported: the builder must check the " +
        "logic script against the registry entry.",
    );
  }

  const registry = readRegistry(p.settingsUtxo);
  const forwarderHash = counterScriptHash(p.forwarderScript);
  const delegate = registry.get(forwarderHash);
  if (delegate === undefined) {
    throw new Error(
      `The forwarder (${forwarderHash}) is not registered in the settings ` +
        "registry; register it (Propose + Apply) before spending its UTxOs.",
    );
  }

  const datum = counterDatumFromUtxo(p.forwarderUtxo);
  const continuation = counterDatumToData({
    count: datum.count + 1,
    owner: datum.owner,
    prevInput: {
      txHash: p.forwarderUtxo.input.txHash,
      outputIndex: p.forwarderUtxo.input.outputIndex,
    },
  });

  applyAuthorization(
    p.txBuilder,
    { kind: "script", hash: delegate },
    p.logicAuthorizer,
    networkId,
  );

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
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    )
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
  const networkId = networkIdOf(network);

  const datum: CounterDatum = counterDatumFromUtxo(p.v1Utxo);
  if (datum.owner.kind !== "key") {
    throw new Error(
      "The demo upgrade builder requires the UTxO owner to be a key credential " +
        "(it signs to consent). Script owners need a custom builder.",
    );
  }
  p.txBuilder.requiredSignerHash(datum.owner.hash);

  if (p.migrationAuthorizer.manual) {
    throw new Error(
      "`migrationAuthorizer.manual` is not supported: the builder must check " +
        "the migration script against the registry entry.",
    );
  }

  const registry = readRegistry(p.settingsUtxo);
  const v1Hash = counterScriptHash(p.v1Script);
  const delegate = registry.get(v1Hash);
  if (delegate === undefined) {
    throw new Error(
      `V1 (${v1Hash}) is not registered in the settings registry; register the ` +
        "migration script (Propose + Apply) before upgrading.",
    );
  }

  applyAuthorization(
    p.txBuilder,
    { kind: "script", hash: delegate },
    p.migrationAuthorizer,
    networkId,
  );

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
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    )
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

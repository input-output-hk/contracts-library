/**
 * Transaction building blocks for the upgradeability building block (MeshJS).
 *
 * The registry lives in a settings UTxO (#20); changing it reuses the settings
 * builders. `addDelegateInvocation` wires what every forwarded (forced) or
 * migrated (opt-in) transaction needs: the registered delegate's withdraw-0
 * and the settings reference input. A protocol's own builders add their
 * inputs, outputs and mints around it. The `counter_*` demo builders, in
 * `@contracts-library/meshjs/examples/upgradeability`, show how.
 */

import type { MeshTxBuilder, Network, UTxO } from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import {
  buildApplyTx,
  buildProposeTx,
  type ApplyParams,
  type ProposeParams,
} from "../settings/settings";
import { registryFromUtxo, registryToData } from "./datum";
import type { Registry } from "./types";

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
 * Apply a matured registry proposal: exactly the settings `Apply`. The
 * registry is just the settings value, so nothing new is wired here.
 */
export async function buildRegistryApplyTx(p: ApplyParams): Promise<string> {
  return await buildApplyTx(p);
}

export interface DelegateInvocationParams {
  txBuilder: MeshTxBuilder;
  /**
   * The registry key: the script hash of the forwarder (forced) or the V1
   * validator (opt-in) being used in this transaction.
   */
  ownHash: string;
  /**
   * How to invoke the registered delegate: inline (`scriptCbor`) or by
   * reference (`reference`). Its hash is checked against the registry entry.
   */
  delegateAuthorizer: ScriptAuthorizer;
  /** The settings UTxO holding the registry (added as a reference input). */
  settingsUtxo: UTxO;
  network?: Network;
}

/**
 * Wire the delegate registered for `ownHash`: its withdraw-0 and the settings
 * reference input it is read from. Returns the delegate's script hash.
 *
 * Throws early if `ownHash` is not registered or the authorizer is not the
 * registered script, so a stale registry surfaces as a clear error instead of
 * a rejected transaction. A `manual` authorizer is refused for the same
 * reason: its script cannot be checked against the registry.
 */
export function addDelegateInvocation(p: DelegateInvocationParams): string {
  if (p.delegateAuthorizer.manual) {
    throw new Error(
      "A `manual` delegate authorizer is not supported: the delegate script " +
        "must be checked against the registry entry.",
    );
  }
  const delegate = readRegistry(p.settingsUtxo).get(p.ownHash);
  if (delegate === undefined) {
    throw new Error(
      `${p.ownHash} is not registered in the settings registry; register it ` +
        "(Propose + Apply) first.",
    );
  }
  applyAuthorization(
    p.txBuilder,
    { kind: "script", hash: delegate },
    p.delegateAuthorizer,
    p.network === "mainnet" ? 1 : 0,
  );
  p.txBuilder.readOnlyTxInReference(
    p.settingsUtxo.input.txHash,
    p.settingsUtxo.input.outputIndex,
  );
  return delegate;
}

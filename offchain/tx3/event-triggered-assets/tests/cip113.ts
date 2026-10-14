/**
 * Test-only CIP-113 core helpers for the event-triggered assets tx3 e2e.
 *
 * The tx3 protocol cannot apply parameters to scripts, so the applied core and
 * module scripts are computed here with the vendored blueprints and the
 * library's `applyBond`, then handed to the protocol through its environment.
 * Both the vendored e2e helpers and the library builders return
 * `applyParamsToScript`'s double-CBOR form; tx3 hashes the exact bytes it is
 * handed and the Plutus evaluator CBOR-decodes them, so every script handed
 * over is reduced to its single-CBOR payload with `unwrapCborBytes`.
 */

import {
  deserializeAddress,
  pubKeyAddress,
  scriptAddress,
  serializeAddressObj,
} from "@meshsdk/core";

import {
  applyBond,
  applyScript,
  scriptHashOf,
  stripCborWrappers,
  type Bond,
  type CoreConfig,
  type CoreDeployment,
  type CoreScripts,
  type Credential,
} from "@contracts-library/meshjs";

import { issuanceMintCompiledCode } from "../../../meshjs/e2e/src/cip113/blueprint";
import { applyCoreScripts } from "../../../meshjs/e2e/src/cip113/scripts";
import { issuanceTemplate } from "../../../meshjs/e2e/src/cip113/template";

export {
  applyCoreScripts,
  applyScript,
  issuanceMintCompiledCode,
  issuanceTemplate,
  scriptHashOf,
  stripCborWrappers,
};
export type { CoreConfig, CoreScripts };

export const NETWORK_ID = 0;

export const bytes = (value: string): Uint8Array =>
  Uint8Array.from(Buffer.from(value, "hex"));
export const hexOf = (value: Uint8Array): string =>
  Buffer.from(value).toString("hex");

export const refParts = (
  ref: string,
): { txHash: string; outputIndex: number } => {
  const [txHash, outputIndex] = ref.split("#");
  return { txHash, outputIndex: Number(outputIndex) };
};

/** `txHash#index` refs in the ledger's canonical order (txHash, index). */
export function sortRefs(refs: string[]): string[] {
  return [...refs].sort((a, b) => {
    const [ah, ai] = a.split("#");
    const [bh, bi] = b.split("#");
    const x = ah.toLowerCase();
    const y = bh.toLowerCase();
    if (x !== y) return x < y ? -1 : 1;
    return Number(ai) - Number(bi);
  });
}

export function refIndexOf(refs: string[], target: string): number {
  const index = sortRefs(refs).indexOf(target);
  if (index < 0) throw new Error(`reference input ${target} not in set`);
  return index;
}

/**
 * Withdrawals are ordered by the ledger with every script credential before
 * every verification key, bytewise within each group. Every withdrawal in this
 * suite is a script credential, so a plain bytewise sort is the ledger order.
 */
export function withdrawalIndexOf(hashes: string[], target: string): number {
  const index = [...hashes]
    .map((h) => h.toLowerCase())
    .sort()
    .indexOf(target.toLowerCase());
  if (index < 0) throw new Error(`withdrawal ${target} not in set`);
  return index;
}

// ------------------------------------------------------------------ addresses

/** Enterprise script address (payment credential only). */
export function scriptAddr(hash: string): string {
  return serializeAddressObj(scriptAddress(hash), NETWORK_ID);
}

/** PLB-custodied base address: script payment + owner stake credential. */
export function plbAddr(
  plbHash: string,
  stakeHash: string,
  stakeIsScript: boolean,
): string {
  return serializeAddressObj(
    scriptAddress(plbHash, stakeHash, stakeIsScript),
    NETWORK_ID,
  );
}

/** Base address with key payment and key stake. */
export function baseAddr(paymentHash: string, stakeHash: string): string {
  return serializeAddressObj(pubKeyAddress(paymentHash, stakeHash), NETWORK_ID);
}

/** Hex bytes of a script's reward (stake) address, for tx3 `Bytes` env. */
export const rewardAddrHex = (hash: string): string => `f0${hash}`;

/**
 * The Aiken `Address` **data** pieces of a bech32 address, for tx3 custom
 * types: `Constr 0 [PaymentCredential, Option<Referenced<Credential>>]`. The
 * tx3 `Address` primitive serializes as raw address bytes, which a validator
 * decoding `Address` from data cannot read, so redeemers that carry an address
 * must build the constructor form explicitly.
 */
export function addressParts(address: string): {
  payment_credential: Record<string, unknown>;
  stake_credential: Record<string, unknown>;
} {
  const a = deserializeAddress(address);
  const payment =
    a.pubKeyHash !== ""
      ? { Key: { hash: bytes(a.pubKeyHash) } }
      : { Script: { hash: bytes(a.scriptHash) } };
  const stake =
    a.stakeCredentialHash !== ""
      ? {
          Some: {
            stake: {
              Inline: {
                credential: { Key: { hash: bytes(a.stakeCredentialHash) } },
              },
            },
          },
        }
      : a.stakeScriptCredentialHash !== ""
        ? {
            Some: {
              stake: {
                Inline: {
                  credential: {
                    Script: { hash: bytes(a.stakeScriptCredentialHash) },
                  },
                },
              },
            },
          }
        : { None: {} };
  return { payment_credential: payment, stake_credential: stake };
}

/** `redeem`'s payout args for a bech32 destination, ready to spread. */
export function payoutArgs(address: string): {
  payout_address: string;
  payout_address_data: Record<string, unknown>;
} {
  const { payment_credential, stake_credential } = addressParts(address);
  return {
    payout_address: address,
    payout_address_data: { payment_credential, stake_credential },
  };
}

// --------------------------------------------------------------- bond scripts

export interface BondParams {
  registryNodeCs: string;
  paramsPolicy: string;
  issuer: Credential;
  vaultNftName: string;
  principal: number;
  interval: number;
  amounts: number[];
}

/**
 * Apply one bond with the library's `applyBond`, which resolves the dependency
 * order (transfer / third-party / vault-NFT → vault → minting logic →
 * `issuance_mint` → coupon policy). It only needs the registry-node policy, the
 * protocol-params policy, the network id and the raw `issuance_mint` code — all
 * of which the vendored core bootstrap provides.
 */
export function bondScripts(p: BondParams): Bond {
  const deployment = {
    config: { networkId: NETWORK_ID },
    core: { registryNodeCs: p.registryNodeCs, paramsPolicy: p.paramsPolicy },
    refs: {},
    issuanceMintCode: issuanceMintCompiledCode,
  } as unknown as CoreDeployment;

  return applyBond(deployment, {
    principal: p.principal,
    interval: p.interval,
    amounts: p.amounts,
    issuer: p.issuer,
    vaultNftName: p.vaultNftName,
  });
}

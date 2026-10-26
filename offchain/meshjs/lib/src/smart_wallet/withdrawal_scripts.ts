/**
 * The two reference delegation withdrawal scripts (`spending_limit`,
 * `spending_window`).
 *
 * These are withdraw-0 staking scripts delegated by a smart wallet (spender
 * scripts; depositor scripts use the same mechanism). Their `wallet` parameter
 * is the wallet's payment credential (a `Credential`, normally
 * `{ kind: "script", hash: walletHash }`) and `walletTokenName` is the asset
 * name of the wallet's identifying NFT. Together they pin a script instance to
 * one wallet and let every delegated read identify the authenticated wallet
 * UTxO — the known limitation noted in the spec's roadmap.
 */

import {
  applyParamsToScript,
  mConStr0,
  resolveScriptHash,
  serializeRewardAddress,
  type Data,
  type MeshTxBuilder,
  type PlutusScript,
} from "@meshsdk/core";
import { CredentialType, Serialization } from "@meshsdk/core-cst";

import {
  assetAllowListCode,
  assetDenyListCode,
  assetDepositAllowListCode,
  assetDepositDenyListCode,
  fullRecipientAllowListCode,
  fullRecipientDenyListCode,
  paymentStakingAllowListCode,
  paymentStakingDenyListCode,
  plutusVersion,
  spendingLimitCode,
  spendingPeriodLimitCode,
  spendingWindowCode,
} from "./blueprint";
import {
  assetAllowListParamsToData,
  assetDenyListParamsToData,
  assetDepositAllowListParamsToData,
  assetDepositDenyListParamsToData,
  fullRecipientAllowListParamsToData,
  fullRecipientDenyListParamsToData,
  paymentStakingAllowListParamsToData,
  paymentStakingDenyListParamsToData,
  spendingLimitParamsToData,
  spendingPeriodLimitParamsToData,
  spendingWindowParamsToData,
} from "./datum";
import type {
  AssetAllowListParams,
  AssetDenyListParams,
  AssetDepositAllowListParams,
  AssetDepositDenyListParams,
  FullRecipientAllowListParams,
  FullRecipientDenyListParams,
  PaymentStakingAllowListParams,
  PaymentStakingDenyListParams,
  SpendingLimitParams,
  SpendingPeriodLimitParams,
  SpendingWindowParams,
} from "./types";

/**
 * Rewrite only the wallet's own withdrawal-script certificates in a serialized
 * transaction from the legacy forms MeshJS emits (`stake_registration` /
 * `stake_deregistration`) to the Conway certifying forms:
 *
 *   `stake_registration`   -> `reg_cert`    ([7, credential, deposit])
 *   `stake_deregistration` -> `unreg_cert`  ([8, credential, refund])
 *
 * Only the Conway forms trigger the CIP-69 `publish` script purpose; a legacy
 * cert would leave the attached certificate redeemer extraneous and the ledger
 * rejects the transaction. Unrelated certificates are left untouched, and the
 * deposit/refund is the protocol's `keyDeposit`, matching what MeshJS already
 * charges/refunds for the legacy cert types.
 */
export function rewriteWithdrawalCertificates(
  txHex: string,
  targetScriptHashes: ReadonlySet<string>,
  keyDeposit: bigint,
): string {
  const tx = Serialization.Transaction.fromCbor(txHex);
  const body = tx.body();
  const certs = body.certs();
  if (!certs) return txHex;

  let swapped = false;
  const rewritten = certs.values().map((cert) => {
    const kind = cert.kind();
    if (kind === 0) {
      const stake = cert.asStakeRegistration();
      if (!stake) return cert;
      const credential = stake.stakeCredential();
      if (!targetScript(credential, targetScriptHashes)) return cert;
      swapped = true;
      return Serialization.Certificate.newRegistrationCert(
        new Serialization.Registration(credential, keyDeposit),
      );
    }
    if (kind === 1) {
      const stake = cert.asStakeDeregistration();
      if (!stake) return cert;
      const credential = stake.stakeCredential();
      if (!targetScript(credential, targetScriptHashes)) return cert;
      swapped = true;
      return Serialization.Certificate.newUnregistrationCert(
        new Serialization.Unregistration(credential, keyDeposit),
      );
    }
    return cert;
  });

  if (!swapped) return txHex;

  certs.setValues(rewritten);
  body.setCerts(certs);
  tx.setBody(body);
  return tx.toCbor();
}

function targetScript(
  credential: { type: number; hash: string },
  targetScriptHashes: ReadonlySet<string>,
): boolean {
  return (
    credential.type === CredentialType.ScriptHash &&
    targetScriptHashes.has(credential.hash.toLowerCase())
  );
}

function keyDepositFrom(
  protocolParams: { keyDeposit?: number } | undefined,
): bigint {
  if (protocolParams?.keyDeposit === undefined) {
    throw new Error(
      "Protocol parameters with keyDeposit are required to register or deregister withdrawal scripts.",
    );
  }
  return BigInt(protocolParams.keyDeposit);
}

const serializerTargets = new WeakMap<object, Set<string>>();

/**
 * Wrap a builder's serializer so both of its serialization paths run through
 * `rewriteWithdrawalCertificates`: the mock serialization used for fee
 * estimation and the final serialization. The target set accumulates the
 * scripts registered or deregistered through this builder. MeshJS has no public
 * API for the Conway certifying cert forms, so the swap happens right where the
 * builder emits bytes.
 */
function patchTxBuilderSerializer(
  txBuilder: MeshTxBuilder,
  scriptHash: string,
): void {
  const serializer = txBuilder.serializer;
  const existing = serializerTargets.get(serializer);
  const targets = existing ?? new Set<string>();
  if (!existing) {
    serializerTargets.set(serializer, targets);

    const serializeBody = serializer.serializeTxBody.bind(serializer);
    const serializeMock =
      serializer.serializeTxBodyWithMockSignatures.bind(serializer);

    serializer.serializeTxBody = (body, params) =>
      rewriteWithdrawalCertificates(
        serializeBody(body, params),
        targets,
        keyDepositFrom(
          params ??
            (serializer as { protocolParams?: { keyDeposit?: number } })
              .protocolParams,
        ),
      );
    serializer.serializeTxBodyWithMockSignatures = (body, params) =>
      rewriteWithdrawalCertificates(
        serializeMock(body, params),
        targets,
        keyDepositFrom(
          params ??
            (serializer as { protocolParams?: { keyDeposit?: number } })
              .protocolParams,
        ),
      );
  }
  targets.add(scriptHash.toLowerCase());
}

/** Parameterized `spending_limit` script: net outflow stays below `bound`. */
/** Apply a withdraw-script's static code to its record parameter. */
function applyScript(code: string, params: Data): PlutusScript {
  return {
    code: applyParamsToScript(code, [params], "Mesh"),
    version: plutusVersion,
  };
}

export function spendingLimitScript(params: SpendingLimitParams): PlutusScript {
  return applyScript(spendingLimitCode, spendingLimitParamsToData(params));
}

/** Parameterized `spending_window` script: at most one spend per `window`. */
export function spendingWindowScript(
  params: SpendingWindowParams,
): PlutusScript {
  return applyScript(spendingWindowCode, spendingWindowParamsToData(params));
}

/** Parameterized `spending_period_limit` script: `max_spend` per `interval`. */
export function spendingPeriodLimitScript(
  params: SpendingPeriodLimitParams,
): PlutusScript {
  return applyScript(
    spendingPeriodLimitCode,
    spendingPeriodLimitParamsToData(params),
  );
}

/** Parameterized `full_recipient_allow_list` script (spender). */
export function fullRecipientAllowListScript(
  params: FullRecipientAllowListParams,
): PlutusScript {
  return applyScript(
    fullRecipientAllowListCode,
    fullRecipientAllowListParamsToData(params),
  );
}

/** Parameterized `full_recipient_deny_list` script (spender). */
export function fullRecipientDenyListScript(
  params: FullRecipientDenyListParams,
): PlutusScript {
  return applyScript(
    fullRecipientDenyListCode,
    fullRecipientDenyListParamsToData(params),
  );
}

/** Parameterized `payment_staking_allow_list` script (spender). */
export function paymentStakingAllowListScript(
  params: PaymentStakingAllowListParams,
): PlutusScript {
  return applyScript(
    paymentStakingAllowListCode,
    paymentStakingAllowListParamsToData(params),
  );
}

/** Parameterized `payment_staking_deny_list` script (spender). */
export function paymentStakingDenyListScript(
  params: PaymentStakingDenyListParams,
): PlutusScript {
  return applyScript(
    paymentStakingDenyListCode,
    paymentStakingDenyListParamsToData(params),
  );
}

/** Parameterized `asset_allow_list` script (spender). */
export function assetAllowListScript(
  params: AssetAllowListParams,
): PlutusScript {
  return applyScript(assetAllowListCode, assetAllowListParamsToData(params));
}

/** Parameterized `asset_deny_list` script (spender). */
export function assetDenyListScript(params: AssetDenyListParams): PlutusScript {
  return applyScript(assetDenyListCode, assetDenyListParamsToData(params));
}

/** Parameterized `asset_deposit_allow_list` script (depositor). */
export function assetDepositAllowListScript(
  params: AssetDepositAllowListParams,
): PlutusScript {
  return applyScript(
    assetDepositAllowListCode,
    assetDepositAllowListParamsToData(params),
  );
}

/** Parameterized `asset_deposit_deny_list` script (depositor). */
export function assetDepositDenyListScript(
  params: AssetDepositDenyListParams,
): PlutusScript {
  return applyScript(
    assetDepositDenyListCode,
    assetDepositDenyListParamsToData(params),
  );
}

/** Address of a withdrawal script's reward account (stake credential). */
export function withdrawalScriptAddress(
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): string {
  return serializeRewardAddress(
    resolveScriptHash(script.code, script.version),
    true,
    networkId,
  );
}

/**
 * Publish a withdrawal script's stake credential: emit a `RegisterCredential`
 * certificate and wire in the script witness + cert redeemer so its `publish`
 * handler runs (CIP-69). The wallet requires this on `Mint` /
 * `UpdatePermissions` whenever a script is added to the `spenders` or
 * `depositors` map.
 */
export function registerWithdrawalScript(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): void {
  const scriptHash = resolveScriptHash(script.code, script.version);
  patchTxBuilderSerializer(txBuilder, scriptHash);
  const rewardAddress = serializeRewardAddress(scriptHash, true, networkId);
  txBuilder
    .registerStakeCertificate(rewardAddress)
    .certificateScript(script.code, script.version)
    .certificateRedeemerValue(mConStr0([]));
}

/**
 * Unregister a withdrawal script's stake credential: emit an
 * `UnregisterCredential` certificate and wire in the script witness + cert
 * redeemer so its `publish` handler runs (CIP-69). The wallet requires this on
 * `UpdatePermissions` (removed scripts) and `Close` (every script in either
 * map).
 */
export function deregisterWithdrawalScript(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): void {
  const scriptHash = resolveScriptHash(script.code, script.version);
  patchTxBuilderSerializer(txBuilder, scriptHash);
  const rewardAddress = serializeRewardAddress(scriptHash, true, networkId);
  txBuilder
    .deregisterStakeCertificate(rewardAddress)
    .certificateScript(script.code, script.version)
    .certificateRedeemerValue(mConStr0([]));
}

/**
 * Invoke a delegated withdrawal script as a withdraw-0 reward withdrawal (so it
 * runs and approves). The wallet requires every script in the relevant map to
 * be invoked: `spenders` on every `Spend`, `depositors` on every `Deposit`.
 */
export function invokeWithdrawalScript(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): void {
  const rewardAddress = serializeRewardAddress(
    resolveScriptHash(script.code, script.version),
    true,
    networkId,
  );
  txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(rewardAddress, "0")
    .withdrawalScript(script.code)
    .withdrawalRedeemerValue(mConStr0([]));
}

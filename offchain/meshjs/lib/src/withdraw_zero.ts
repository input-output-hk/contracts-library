/**
 * Stake registration for scripts that run under the withdraw-0 convention.
 *
 * A withdraw-0 script only runs once its stake credential is registered. Since
 * Conway, the deposit-carrying registration certificate (`reg_cert`) runs the
 * script's `publish` handler; the older `stake_registration` cert needs no
 * script approval but is marked for removal. MeshJS only emits the older
 * forms, so these helpers rewrite them into the Conway forms at serialization.
 * Mirrors `onchain/lib/withdraw_zero.ak`.
 */

import {
  mConStr0,
  resolveScriptHash,
  serializeRewardAddress,
  type MeshTxBuilder,
  type PlutusScript,
} from "@meshsdk/core";
import { CredentialType, Serialization } from "@meshsdk/core-cst";

/**
 * Rewrite only the targeted withdrawal-script certificates in a serialized
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

/**
 * Publish a withdrawal script's stake credential: emit a `RegisterCredential`
 * certificate and wire in the script witness + cert redeemer so its `publish`
 * handler runs (CIP-69). The smart wallet requires this on `Mint` /
 * `UpdatePermissions` whenever a script is added to the `spenders` or
 * `depositors` map; an upgradeability delegate needs it once before its
 * first withdraw-0.
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
 * redeemer so its `publish` handler runs (CIP-69). The smart wallet requires this on
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

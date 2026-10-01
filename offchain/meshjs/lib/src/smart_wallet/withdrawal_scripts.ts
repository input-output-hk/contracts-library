/**
 * The two reference withdrawal scripts (`spending_limit`, `spending_window`).
 *
 * These are withdraw-0 staking scripts delegated by a smart wallet. Their `wallet`
 * parameter is the wallet's payment credential (a `Credential`, normally
 * `{ kind: "script", hash: walletHash }`), which pins a script instance to one
 * wallet — the known limitation noted in the spec's roadmap.
 */

import {
  applyParamsToScript,
  mConStr0,
  resolveScriptHash,
  serializePlutusScript,
  serializeRewardAddress,
  type MeshTxBuilder,
  type PlutusScript,
} from "@meshsdk/core";
import { Serialization } from "@meshsdk/core-cst";

import {
  plutusVersion,
  spendingLimitCode,
  spendingWindowCode,
} from "./blueprint";
import { spendingLimitParamsToData, spendingWindowParamsToData } from "./datum";
import type { SpendingLimitParams, SpendingWindowParams } from "./types";

/** Stake-address deposit charged/refunded for `reg_cert` / `unreg_cert`. */
const STAKE_ADDRESS_DEPOSIT = 2_000_000n;

/**
 * MeshJS only exposes legacy stake certificates (`stake_registration` /
 * `stake_deregistration`). Those do not trigger the CIP-69 `publish` script
 * purpose, so a withdrawal script's cert redeemer would be left extraneous and
 * the ledger rejects the transaction.
 *
 * There is no public API for the Conway certifying forms, so we post-process
 * every serialized transaction right where the builder produces it: we wrap the
 * builder's serializer and rewrite the legacy certificates to their Conway
 * equivalents in the serialized bytes.
 *
 *   `stake_registration`  ->  `reg_cert`   ([7, credential, deposit])
 *   `stake_deregistration` -> `unreg_cert` ([8, credential, refund])
 *
 * The rewrite is applied both to the mock serialization used for fee estimation
 * and to the final serialization, so the fee accounts for the deposit field. The
 * balance is unaffected: MeshJS still charges/refunds `keyDeposit` for the legacy
 * cert types, which is exactly the deposit the Conway forms carry.
 */
function swapCertificates(txHex: string): string {
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
      swapped = true;
      return Serialization.Certificate.newRegistrationCert(
        new Serialization.Registration(
          stake.stakeCredential(),
          STAKE_ADDRESS_DEPOSIT,
        ),
      );
    }
    if (kind === 1) {
      const stake = cert.asStakeDeregistration();
      if (!stake) return cert;
      swapped = true;
      return Serialization.Certificate.newUnregistrationCert(
        new Serialization.Unregistration(
          stake.stakeCredential(),
          STAKE_ADDRESS_DEPOSIT,
        ),
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

const patchedSerializers = new WeakSet<object>();

function patchTxBuilderSerializer(txBuilder: MeshTxBuilder): void {
  const serializer = txBuilder.serializer;
  if (patchedSerializers.has(serializer)) return;
  patchedSerializers.add(serializer);

  const serializeBody = serializer.serializeTxBody.bind(serializer);
  const serializeMock =
    serializer.serializeTxBodyWithMockSignatures.bind(serializer);

  serializer.serializeTxBody = (body, params) =>
    swapCertificates(serializeBody(body, params));
  serializer.serializeTxBodyWithMockSignatures = (body, params) =>
    swapCertificates(serializeMock(body, params));
}

/** Parameterized `spending_limit` script: net outflow stays below `bound`. */
export function spendingLimitScript(params: SpendingLimitParams): PlutusScript {
  return {
    code: applyParamsToScript(
      spendingLimitCode,
      spendingLimitParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `spending_window` script: at most one spend per `window`. */
export function spendingWindowScript(
  params: SpendingWindowParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      spendingWindowCode,
      spendingWindowParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Address of a withdrawal script's reward account (stake credential). */
export function withdrawalScriptAddress(
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

/**
 * Publish a withdrawal script's stake credential: emit a `RegisterCredential`
 * certificate and wire in the script witness + cert redeemer so its `publish`
 * handler runs (CIP-69). The wallet requires this on `Mint` / `UpdateConfig`
 * whenever a script is added to the `withdrawals` map.
 */
export function registerWithdrawalScript(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): void {
  patchTxBuilderSerializer(txBuilder);
  const rewardAddress = serializeRewardAddress(
    resolveScriptHash(script.code, script.version),
    true,
    networkId,
  );
  txBuilder
    .registerStakeCertificate(rewardAddress)
    .certificateScript(script.code, script.version)
    .certificateRedeemerValue(mConStr0([]));
}

/**
 * Unregister a withdrawal script's stake credential: emit an
 * `UnregisterCredential` certificate and wire in the script witness + cert
 * redeemer so its `publish` handler runs (CIP-69). The wallet requires this on
 * `UpdateConfig` (removed scripts) and `Close`.
 */
export function deregisterWithdrawalScript(
  txBuilder: MeshTxBuilder,
  script: PlutusScript,
  networkId: 0 | 1 = 0,
): void {
  patchTxBuilderSerializer(txBuilder);
  const rewardAddress = serializeRewardAddress(
    resolveScriptHash(script.code, script.version),
    true,
    networkId,
  );
  txBuilder
    .deregisterStakeCertificate(rewardAddress)
    .certificateScript(script.code, script.version)
    .certificateRedeemerValue(mConStr0([]));
}

/**
 * Invoke a delegated withdrawal script as a withdraw-0 reward withdrawal (so it
 * runs and approves). The wallet requires every script in its `withdrawals` map
 * to be invoked on every `Spend`.
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

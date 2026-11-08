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
  type MeshTxBuilder,
  type PlutusScript,
} from "@meshsdk/core";

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

// Shared with every withdraw-0 script; re-exported to keep this module's API.
export {
  deregisterWithdrawalScript,
  registerWithdrawalScript,
} from "../withdraw_zero";

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

/** Parameterized `spending_period_limit` script: `max_spend` per `interval`. */
export function spendingPeriodLimitScript(
  params: SpendingPeriodLimitParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      spendingPeriodLimitCode,
      spendingPeriodLimitParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `full_recipient_allow_list` script (spender). */
export function fullRecipientAllowListScript(
  params: FullRecipientAllowListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      fullRecipientAllowListCode,
      fullRecipientAllowListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `full_recipient_deny_list` script (spender). */
export function fullRecipientDenyListScript(
  params: FullRecipientDenyListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      fullRecipientDenyListCode,
      fullRecipientDenyListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `payment_staking_allow_list` script (spender). */
export function paymentStakingAllowListScript(
  params: PaymentStakingAllowListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      paymentStakingAllowListCode,
      paymentStakingAllowListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `payment_staking_deny_list` script (spender). */
export function paymentStakingDenyListScript(
  params: PaymentStakingDenyListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      paymentStakingDenyListCode,
      paymentStakingDenyListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `asset_allow_list` script (spender). */
export function assetAllowListScript(
  params: AssetAllowListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      assetAllowListCode,
      assetAllowListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `asset_deny_list` script (spender). */
export function assetDenyListScript(params: AssetDenyListParams): PlutusScript {
  return {
    code: applyParamsToScript(
      assetDenyListCode,
      assetDenyListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `asset_deposit_allow_list` script (depositor). */
export function assetDepositAllowListScript(
  params: AssetDepositAllowListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      assetDepositAllowListCode,
      assetDepositAllowListParamsToData(params),
      "Mesh",
    ),
    version: plutusVersion,
  };
}

/** Parameterized `asset_deposit_deny_list` script (depositor). */
export function assetDepositDenyListScript(
  params: AssetDepositDenyListParams,
): PlutusScript {
  return {
    code: applyParamsToScript(
      assetDepositDenyListCode,
      assetDepositDenyListParamsToData(params),
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
  return serializeRewardAddress(
    resolveScriptHash(script.code, script.version),
    true,
    networkId,
  );
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

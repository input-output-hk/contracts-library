/**
 * Transaction builders for linear vesting (MeshJS).
 *
 * Implements the action set in specs/vesting/linear-vesting.md §4:
 *   - `buildLockTx`   create a vesting instance (no script runs).
 *   - `buildClaimTx`  withdraw the vested portion (beneficiary).
 *   - `buildCancelTx` recover the remainder after recoveryTime (locker).
 *
 * These return an unsigned transaction (hex) from a configured `MeshTxBuilder`.
 * Signing/submission is the caller's wallet's responsibility.
 */

import {
  applyCborEncoding,
  serializePlutusScript,
  SLOT_CONFIG_NETWORK,
  unixTimeToEnclosingSlot,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "./authorization";
import { compiledCode, plutusVersion } from "./blueprint";
import {
  cancelRedeemer,
  claimRedeemer,
  requiredRemainder,
  vestingDatumToData,
} from "./datum";
import type { VestedAsset, VestingDatum } from "./types";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

/** Default floor (in lovelace) for the continuing output's ada. The validator
 * permits extra, schedule-unprotected ada, so bumping to satisfy min-utxo is
 * always safe (spec §7, "Min-ada and extra value"). */
const DEFAULT_MIN_UTXO_LOVELACE = 1_500_000n;

/** The Plutus V3 script in the form MeshJS expects (double-CBOR-encoded). */
export function vestingScript(): PlutusScript {
  return { code: applyCborEncoding(compiledCode), version: plutusVersion };
}

/** Bech32 address of the vesting script for the given network id (0 = test). */
export function vestingScriptAddress(networkId = 0): string {
  return serializePlutusScript(vestingScript(), undefined, networkId).address;
}

function assetUnit(policyId: string, assetName: string): string {
  return policyId === "" ? "lovelace" : policyId + assetName;
}

/** Continuing-output assets: the required remainder, with ada floored to
 * `minLovelace` (adding an ada entry if the bundle has none). */
function remainderToAssets(
  remainder: VestedAsset[],
  minLovelace: bigint,
): Asset[] {
  const assets: Asset[] = [];
  let hasAda = false;
  for (const a of remainder) {
    const unit = assetUnit(a.policyId, a.assetName);
    if (unit === "lovelace") {
      hasAda = true;
      const q = a.total < minLovelace ? minLovelace : a.total;
      assets.push({ unit, quantity: q.toString() });
    } else {
      assets.push({ unit, quantity: a.total.toString() });
    }
  }
  if (!hasAda) {
    assets.unshift({ unit: "lovelace", quantity: minLovelace.toString() });
  }
  return assets;
}

export interface LockParams {
  txBuilder: MeshTxBuilder;
  /** The vesting terms. `startTime`/`endTime` are POSIX milliseconds. */
  datum: VestingDatum;
  /** Wallet UTxOs to fund the bundle + fees. */
  utxos: UTxO[];
  /** Wallet change address. */
  changeAddress: string;
  /**
   * Exact assets to lock. Defaults to the datum's `vesting` bundle with ada
   * floored to `minUtxoLovelace`. Override to lock extra ada/tokens.
   */
  lockAssets?: Asset[];
  networkId?: number;
  minUtxoLovelace?: bigint;
}

/** Build a Lock transaction: send the bundle to the script with an inline datum. */
export async function buildLockTx(p: LockParams): Promise<string> {
  const { startTime, endTime, recoveryTime } = p.datum;
  if (!(startTime < endTime && endTime < recoveryTime)) {
    throw new Error(
      "Invalid schedule: require startTime < endTime < recoveryTime",
    );
  }
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;
  const scriptAddr = vestingScriptAddress(p.networkId ?? 0);
  const assets =
    p.lockAssets ??
    remainderToAssets(p.datum.vesting, minLovelace); // full bundle, ada floored

  return await p.txBuilder
    .txOut(scriptAddr, assets)
    .txOutInlineDatumValue(vestingDatumToData(p.datum))
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

export interface ClaimParams {
  txBuilder: MeshTxBuilder;
  /** The script UTxO being claimed. */
  vestingUtxo: UTxO;
  /** Its datum (the value you locked with). */
  datum: VestingDatum;
  /** POSIX ms used as the validity-range lower bound; the on-chain "now". */
  now: number;
  /** Where claimed funds go (also used as change address). */
  beneficiaryAddress: string;
  /** A collateral UTxO (pure-ada) owned by the beneficiary. */
  collateralUtxo: UTxO;
  /** Beneficiary wallet UTxOs to cover fees. */
  utxos: UTxO[];
  /**
   * Required only when `datum.beneficiary` is a **script** credential: how to
   * invoke its approving script (withdraw-0). Ignored for key beneficiaries.
   */
  authorizer?: ScriptAuthorizer;
  network?: Network;
  /**
   * Slot configuration for the time→slot conversion of the validity range.
   * You only need this on a **custom network** (e.g. a local Yaci devnet);
   * for `preview` / `preprod` / `mainnet` leave it unset and the matching
   * config is used automatically from `network`.
   */
  customSlotConfig?: SlotConfig;
  minUtxoLovelace?: bigint;
}

/**
 * Build a Claim transaction. Spends the vesting UTxO, returns the required
 * remainder to the script (unless fully vested), and routes the claimed
 * portion to the beneficiary via change.
 *
 * Works for both key and script beneficiaries: a key beneficiary is added as a
 * required signer; a script beneficiary is authorized via the `authorizer`
 * (see `ScriptAuthorizer`).
 */
export async function buildClaimTx(p: ClaimParams): Promise<string> {
  const { datum, now } = p;
  if (datum.startTime >= datum.endTime) {
    throw new Error("Invalid schedule: startTime must be < endTime");
  }

  const network = p.network ?? "preprod";
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const lowerBoundSlot = unixTimeToEnclosingSlot(now, slotConfig);
  const script = vestingScript();
  const { input, output } = p.vestingUtxo;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(claimRedeemer())
    .txInScript(script.code);

  const remainder = requiredRemainder(datum, now);
  if (remainder.length > 0) {
    p.txBuilder
      .txOut(output.address, remainderToAssets(remainder, minLovelace))
      .txOutInlineDatumValue(vestingDatumToData(datum));
  }

  applyAuthorization(
    p.txBuilder,
    datum.beneficiary,
    p.authorizer,
    networkIdOf(network),
  );

  return await p.txBuilder
    .invalidBefore(lowerBoundSlot)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.beneficiaryAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

export interface CancelParams {
  txBuilder: MeshTxBuilder;
  /** The script UTxO being recovered. */
  vestingUtxo: UTxO;
  /** Its datum. */
  datum: VestingDatum;
  /** POSIX ms used as the validity-range lower bound; must be >= recoveryTime. */
  now: number;
  /** Where recovered funds go (also the change address). */
  lockerAddress: string;
  /** A collateral UTxO (pure-ada) owned by the locker. */
  collateralUtxo: UTxO;
  /** Locker wallet UTxOs to cover fees. */
  utxos: UTxO[];
  /**
   * Required only when `datum.locker` is a **script** credential: how to invoke
   * its approving script (withdraw-0). Ignored for key lockers.
   */
  authorizer?: ScriptAuthorizer;
  network?: Network;
  /**
   * Slot configuration for the time→slot conversion of the validity range.
   * You only need this on a **custom network** (e.g. a local Yaci devnet);
   * for `preview` / `preprod` / `mainnet` leave it unset.
   */
  customSlotConfig?: SlotConfig;
}

/**
 * Build a Cancel transaction: after `recoveryTime`, the locker recovers the
 * entire remaining bundle. No continuing output is produced.
 *
 * Works for both key and script lockers: a key locker is added as a required
 * signer; a script locker is authorized via the `authorizer`.
 */
export async function buildCancelTx(p: CancelParams): Promise<string> {
  const { datum, now } = p;
  if (!(datum.startTime < datum.endTime && datum.endTime < datum.recoveryTime)) {
    throw new Error(
      "Invalid schedule: require startTime < endTime < recoveryTime",
    );
  }
  if (now < datum.recoveryTime) {
    throw new Error("Cannot cancel before recoveryTime");
  }

  const network = p.network ?? "preprod";
  const slotConfig = p.customSlotConfig ?? SLOT_CONFIG_NETWORK[network];
  const lowerBoundSlot = unixTimeToEnclosingSlot(now, slotConfig);
  const script = vestingScript();
  const { input, output } = p.vestingUtxo;

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(input.txHash, input.outputIndex, output.amount, output.address)
    .txInInlineDatumPresent()
    .txInRedeemerValue(cancelRedeemer())
    .txInScript(script.code);

  applyAuthorization(
    p.txBuilder,
    datum.locker,
    p.authorizer,
    networkIdOf(network),
  );

  return await p.txBuilder
    .invalidBefore(lowerBoundSlot)
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.lockerAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}

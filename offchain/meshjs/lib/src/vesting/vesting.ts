/**
 * Transaction builders for linear vesting (MeshJS).
 *
 * Implements the action set in docs/vesting/spec.md §4:
 *   - `buildLockTx`   create a vesting instance (no script runs).
 *   - `buildClaimTx`  withdraw the vested portion (beneficiary).
 *   - `buildCancelTx` recover the remainder after recoveryTime (locker).
 *
 * These return an unsigned transaction (hex) from a configured `MeshTxBuilder`.
 * Signing/submission is the caller's wallet's responsibility.
 */

import {
  type Asset,
  applyCborEncoding,
  type MeshTxBuilder,
  type PlutusScript,
  type SlotConfig,
  serializePlutusScript,
  type UTxO,
} from "@meshsdk/core";

import { applyAuthorization, type ScriptAuthorizer } from "../authorization";
import { finalizeTx, type Network, networkIdOf, slotBound } from "../common";
import { compiledCode, plutusVersion } from "./blueprint";
import {
  assertValidBundle,
  cancelRedeemer,
  claimRedeemer,
  requiredRemainder,
  vestingDatumToData,
} from "./datum";
import type { VestedAsset, VestingDatum } from "./types";

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
 * `minLovelace` (adding an ada entry if the bundle has none). Zero-quantity
 * entries are omitted: they cannot be represented as an output asset. */
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
      if (q > 0n) assets.push({ unit, quantity: q.toString() });
    } else if (a.total > 0n) {
      assets.push({ unit, quantity: a.total.toString() });
    }
  }
  if (!hasAda && minLovelace > 0n) {
    assets.unshift({ unit: "lovelace", quantity: minLovelace.toString() });
  }
  return assets;
}

const ADA_KEY = ":";

/** Canonical case-insensitive key for a datum asset. */
function datumAssetKey(a: VestedAsset): string {
  return `${a.policyId.toLowerCase()}:${a.assetName.toLowerCase()}`;
}

/** Canonical key for a MeshJS `Asset.unit` (`lovelace` or policy+name). */
function unitAssetKey(unit: string): string {
  if (unit === "lovelace") return ADA_KEY;
  if (unit.length < 56) {
    throw new Error(`Invalid asset unit: expected policy id plus asset name`);
  }
  return `${unit.slice(0, 56).toLowerCase()}:${unit.slice(56).toLowerCase()}`;
}

function displayUnit(unit: string): string {
  return unit === "lovelace" ? "ada" : unit;
}

export interface LockValueOptions {
  /** Ada floor used when building the default lock output, in lovelace. */
  minLovelace: bigint;
  /**
   * Permit value beyond the scheduled totals (including unlisted assets)
   * instead of rejecting it. Such value is not schedule-protected: the
   * beneficiary can sweep it on the first partial claim.
   */
  allowUnprotectedValue?: boolean;
  /** Warning sink for intentional unprotected value; defaults to `console`. */
  logger?: Pick<Console, "warn">;
}

/**
 * Validate that a lock output's value matches the datum totals (spec §4.1/I7).
 *
 * Rejects:
 * - a shortfall of any asset listed in `vesting` (it blocks partial claims), and
 * - value above the scheduled totals, unlisted tokens, or unlisted ada beyond
 *   the min-ada floor, unless `allowUnprotectedValue` is set.
 *
 * The ada allowance is `max(listed ada total, minLovelace)`: the output needs
 * min-ada to exist, and that unavoidable floor is always permitted.
 */
export function assertLockValue(
  datum: VestingDatum,
  assets: Asset[],
  options: LockValueOptions,
): void {
  if (options.minLovelace < 0n) {
    throw new Error("Invalid minUtxoLovelace: must be non-negative");
  }

  const actual = new Map<string, { unit: string; quantity: bigint }>();
  for (const asset of assets) {
    if (!/^\d+$/.test(asset.quantity)) {
      throw new Error(
        `Invalid lock value: ${displayUnit(asset.unit)} quantity '${asset.quantity}' is not a non-negative integer`,
      );
    }
    const quantity = BigInt(asset.quantity);
    if (quantity === 0n) continue;
    const key = unitAssetKey(asset.unit);
    const previous = actual.get(key);
    actual.set(key, {
      unit: asset.unit,
      quantity: (previous?.quantity ?? 0n) + quantity,
    });
  }

  const shortfalls: string[] = [];
  for (const required of datum.vesting) {
    const have = actual.get(datumAssetKey(required))?.quantity ?? 0n;
    if (have < required.total) {
      shortfalls.push(
        `${required.total - have} of ${displayUnit(assetUnit(required.policyId, required.assetName))}`,
      );
    }
  }
  if (shortfalls.length > 0) {
    throw new Error(
      `Invalid lock value: output is short of the datum totals (${shortfalls.join(", ")}); a shortfall blocks every partial claim until endTime`,
    );
  }

  const actualAda = actual.get(ADA_KEY)?.quantity ?? 0n;
  if (actualAda < options.minLovelace) {
    throw new Error(
      `Invalid lock value: output holds ${actualAda} lovelace but the min-ada floor is ${options.minLovelace}`,
    );
  }

  // Every listed asset may be present up to its scheduled total. Ada gets the
  // extra min-ada allowance because an output cannot exist without it.
  const allowed = new Map<string, bigint>();
  for (const listed of datum.vesting) {
    allowed.set(datumAssetKey(listed), listed.total);
  }
  const listedAda = allowed.get(ADA_KEY) ?? 0n;
  if (options.minLovelace > listedAda) {
    allowed.set(ADA_KEY, options.minLovelace);
  }

  const excesses: string[] = [];
  for (const [key, asset] of actual) {
    const excess = asset.quantity - (allowed.get(key) ?? 0n);
    if (excess > 0n) {
      excesses.push(`${excess} of ${displayUnit(asset.unit)}`);
    }
  }
  if (excesses.length === 0) return;

  const detail = excesses.join(", ");
  const consequence =
    "value beyond the scheduled totals is not schedule-protected and can be swept by the beneficiary on the first partial claim";
  if (!options.allowUnprotectedValue) {
    throw new Error(
      `Invalid lock value: ${detail} exceeds the datum totals; ${consequence}. Pass allowUnprotectedValue: true only if intentional`,
    );
  }
  (options.logger ?? console).warn(
    `Vesting lock includes unprotected value: ${detail}; ${consequence}.`,
  );
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
   * floored to `minUtxoLovelace`.
   *
   * The value must cover every datum total. Unlisted value and quantities
   * above the scheduled totals are rejected because they are not
   * schedule-protected (the beneficiary can sweep them immediately).
   */
  lockAssets?: Asset[];
  /**
   * Opt in to locking value beyond the datum totals (including unlisted
   * assets). This emits a warning: that value is not schedule-protected and
   * can be swept by the beneficiary on the first partial claim.
   */
  allowUnprotectedValue?: boolean;
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
  assertValidBundle(p.datum.vesting);
  const minLovelace = p.minUtxoLovelace ?? DEFAULT_MIN_UTXO_LOVELACE;
  const scriptAddr = vestingScriptAddress(p.networkId ?? 0);
  const assets =
    p.lockAssets ?? remainderToAssets(p.datum.vesting, minLovelace); // full bundle, ada floored
  assertLockValue(p.datum, assets, {
    minLovelace,
    allowUnprotectedValue: p.allowUnprotectedValue,
  });

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
  const lowerBoundSlot = slotBound(network, now, p.customSlotConfig).slot;
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

  p.txBuilder.invalidBefore(lowerBoundSlot);
  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.beneficiaryAddress,
    utxos: p.utxos,
  });
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
  if (
    !(datum.startTime < datum.endTime && datum.endTime < datum.recoveryTime)
  ) {
    throw new Error(
      "Invalid schedule: require startTime < endTime < recoveryTime",
    );
  }
  if (now < datum.recoveryTime) {
    throw new Error("Cannot cancel before recoveryTime");
  }

  const network = p.network ?? "preprod";
  const lowerBoundSlot = slotBound(network, now, p.customSlotConfig).slot;
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

  p.txBuilder.invalidBefore(lowerBoundSlot);
  return finalizeTx(p.txBuilder, {
    collateral: p.collateralUtxo,
    changeAddress: p.lockerAddress,
    utxos: p.utxos,
  });
}

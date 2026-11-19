/**
 * Validated lock builder for the Tx3 linear-vesting reference.
 *
 * The generated `Client.lock` forwards its parameters directly to the Tx3
 * template, and Tx3 has no conditional comparisons, so the lock-time checks
 * required by spec §4.1 / I7 live here. Call this wrapper instead of
 * `client.lock` when constructing a production lock.
 */

export interface Tx3VestedAsset {
  policy: Uint8Array;
  name: Uint8Array;
  total: number;
}

export interface Tx3VestingDatum {
  beneficiary: unknown;
  locker: unknown;
  vesting: Tx3VestedAsset[];
  start_time: number;
  end_time: number;
  recovery_time: number;
}

/** Wire-form lock input (snake_case, matching the Tx3 template). */
export interface Tx3LockParams {
  ada_total: number;
  vesting_datum: Tx3VestingDatum;
}

/**
 * Accepts either the wire form (`ada_total`/`vesting_datum`) or the
 * camel-cased fields exposed by some generated TypeScript clients.
 */
export interface Tx3LockInput {
  ada_total?: number;
  adaTotal?: number;
  vesting_datum?: Tx3VestingDatum;
  vestingDatum?: Tx3VestingDatum;
}

export interface Tx3LockOptions {
  /**
   * Permit ada above the datum's scheduled total instead of rejecting it.
   * The excess is not schedule-protected and can be swept by the beneficiary
   * on the first partial claim.
   */
  allowUnprotectedValue?: boolean;
  /** Warning sink for intentional unprotected value; defaults to `console`. */
  logger?: Pick<Console, "warn">;
}

function pick<T>(snake: T | undefined, camel: T | undefined, name: string): T {
  if (snake !== undefined && camel !== undefined && snake !== camel) {
    throw new Error(
      `Invalid Tx3 lock: ${name} and its camel-case alias disagree`,
    );
  }
  const value = snake ?? camel;
  if (value === undefined) {
    throw new Error(`Invalid Tx3 lock: missing ${name}`);
  }
  return value;
}

export function normalizeTx3LockParams(input: Tx3LockInput): Tx3LockParams {
  return {
    ada_total: pick(input.ada_total, input.adaTotal, "ada_total"),
    vesting_datum: pick(
      input.vesting_datum,
      input.vestingDatum,
      "vesting_datum",
    ),
  };
}

function requireSafeInt(value: number, label: string): void {
  if (!Number.isSafeInteger(value)) {
    throw new Error(
      `Invalid Tx3 lock: ${label} must be a safe integer (got ${value})`,
    );
  }
}

function isAda(asset: Tx3VestedAsset): boolean {
  return asset.policy.length === 0 && asset.name.length === 0;
}

/**
 * Validate a lock before it is built.
 *
 * The Tx3 reference locks exactly one ada entry (see the protocol README), so
 * a bundle must contain one ada asset. The output amount must equal that
 * total; a larger amount is unprotected surplus and must be opted into
 * explicitly.
 */
export function assertValidTx3Lock(
  params: Tx3LockParams,
  options: Tx3LockOptions = {},
): void {
  const { start_time, end_time, recovery_time, vesting } = params.vesting_datum;

  requireSafeInt(start_time, "start_time");
  requireSafeInt(end_time, "end_time");
  requireSafeInt(recovery_time, "recovery_time");
  if (!(start_time < end_time && end_time < recovery_time)) {
    throw new Error(
      "Invalid Tx3 lock: require start_time < end_time < recovery_time",
    );
  }

  requireSafeInt(params.ada_total, "ada_total");
  if (params.ada_total < 0) {
    throw new Error("Invalid Tx3 lock: ada_total must be non-negative");
  }

  if (vesting.length !== 1 || !isAda(vesting[0])) {
    throw new Error(
      "Invalid Tx3 lock: the Tx3 reference supports exactly one ada entry in vesting",
    );
  }

  const total = vesting[0].total;
  requireSafeInt(total, "vesting[0].total");
  if (total < 0) {
    throw new Error("Invalid Tx3 lock: vesting[0].total must be non-negative");
  }

  if (params.ada_total < total) {
    throw new Error(
      `Invalid Tx3 lock: ada_total is ${params.ada_total} but the datum requires ${total}; a shortfall blocks every partial claim until end_time`,
    );
  }

  const excess = params.ada_total - total;
  if (excess === 0) return;

  const consequence =
    "ada above the scheduled total is not schedule-protected and can be swept by the beneficiary on the first partial claim";
  if (!options.allowUnprotectedValue) {
    throw new Error(
      `Invalid Tx3 lock: ${excess} lovelace exceeds the datum total; ${consequence}. Pass allowUnprotectedValue: true only if intentional`,
    );
  }
  (options.logger ?? console).warn(
    `Tx3 vesting lock includes unprotected value: ${excess} lovelace; ${consequence}.`,
  );
}

/**
 * Validate and build a lock through a generated Tx3 client.
 *
 * ```ts
 * const tx = buildLockTx(client, { ada_total, vesting_datum });
 * ```
 */
export function buildLockTx<R>(
  client: { lock(params: Tx3LockInput): R },
  input: Tx3LockInput,
  options?: Tx3LockOptions,
): R {
  const params = normalizeTx3LockParams(input);
  assertValidTx3Lock(params, options);
  return client.lock(params);
}

/**
 * Off-chain mirror of the counter demo's datums in
 * `onchain/validators/upgradeability/`.
 */

import type { Credential } from "../../common";
import type { SettingsRefParams } from "../../upgradeability/types";

export type { Credential };

/** Reference to a UTxO, mirroring the Aiken `OutputReference` record. */
export interface OutputRef {
  txHash: string;
  outputIndex: number;
}

/** State of the `counter_*` reference validators. */
export interface CounterDatum {
  count: number;
  owner: Credential;
  /**
   * The UTxO this state continues (`null` only at the genesis lock). The
   * validators match their continuation by this tag, so one output can only
   * ever settle the single input it names.
   */
  prevInput: OutputRef | null;
}

/**
 * State written by `counter_logic_stepped`: the original fields plus the
 * amount each tick adds. Counters the first logic wrote still read as the
 * original shape until their next tick converts them (step 1).
 */
export interface SteppedCounterDatum extends CounterDatum {
  step: number;
}

/** Parameters of `counter_migration`: the settings instance plus the V2 target. */
export interface MigrationParams extends SettingsRefParams {
  /** Bech32 address of the V2 validator (the blessed migration target). */
  v2Address: string;
}

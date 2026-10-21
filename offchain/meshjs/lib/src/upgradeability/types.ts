/**
 * Off-chain mirror of the on-chain types in `onchain/lib/upgradeability/`.
 */

import type { Credential } from "../common";

export type { Credential };

/**
 * The upgrade registry: a map from a protocol validator's own script hash
 * (hex) to the script hash of its currently-active delegate (hex).
 *
 * It is stored as the `current` value of a settings UTxO, so changing an entry
 * is a normal settings `Propose` / `Apply` flow (timelock + governance). See
 * `docs/upgradeability/spec.md`.
 */
export type Registry = Map<string, string>;

/** State of the `counter_*` reference validators. */
export interface CounterDatum {
  count: number;
  owner: Credential;
}

/**
 * Parameters of the forwarder / logic / V1 validators: the settings instance
 * that holds the registry. Hashes are hex (Blake2b-224, 56 hex chars).
 */
export interface SettingsRefParams {
  settingsPolicy: string;
  settingsTokenName: string;
}

/** Parameters of `counter_migration`: the settings instance plus the V2 target. */
export interface MigrationParams extends SettingsRefParams {
  /** Bech32 address of the V2 validator (the blessed migration target). */
  v2Address: string;
}

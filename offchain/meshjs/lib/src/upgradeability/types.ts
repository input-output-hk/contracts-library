/**
 * Off-chain mirror of the registry types in `onchain/lib/upgradeability/`.
 */

/**
 * The upgrade registry: a map from a protocol validator's own script hash
 * (hex) to the script hash of its currently-active delegate (hex).
 *
 * It is stored as the `current` value of a settings UTxO, so changing an entry
 * is a normal settings `Propose` / `Apply` flow (timelock + governance). See
 * `docs/upgradeability/spec.md`.
 */
export type Registry = Map<string, string>;

/**
 * Parameters of a validator that reads the registry: the settings instance
 * that holds it. Hashes are hex (Blake2b-224, 56 hex chars).
 */
export interface SettingsRefParams {
  settingsPolicy: string;
  settingsTokenName: string;
}

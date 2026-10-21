/**
 * Contracts Library — MeshJS off-chain package.
 *
 * Contains transaction builders for multiple Aiken validators.
 *
 * Submodules:
 *   - vesting/            Linear vesting
 *   - settings/           Protocol settings
 *   - dao/                DAO governance (proposal, stake, vote)
 *   - upgradeability/     Upgradeability (forced forwarder, opt-in migration)
 */

export * from "./common";
export { applyAuthorization, type ScriptAuthorizer } from "./authorization";

export * from "./vesting";
export * from "./settings";
export * from "./dao";
export * from "./upgradeability";

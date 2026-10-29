/**
 * Contracts Library — MeshJS off-chain package.
 *
 * Contains transaction builders for multiple Aiken validators.
 *
 * Submodules:
 *   - cip113/             CIP-113 core deployment types and helpers
 *   - vesting/            Linear vesting
 *   - settings/           Protocol settings
 *   - dao/                DAO governance (proposal, stake, vote)
 *   - smart_wallet/       Smart wallet with pluggable authorization
 *   - event_triggered/    Tokenized bond (event-triggered assets)
 */

export { applyAuthorization, type ScriptAuthorizer } from "./authorization";
export * from "./cip113";
export * from "./common";
export * from "./dao";
export * from "./event_triggered";
// Both submodules expose this encoder; retain the package's existing export.
export { addressToData } from "./event_triggered";
export * from "./settings";
export * from "./smart_wallet";
export * from "./vesting";

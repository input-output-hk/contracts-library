/**
 * Contracts Library — MeshJS off-chain package.
 *
 * Contains transaction builders for multiple Aiken validators.
 *
 * Submodules:
 *   - vesting/            Linear vesting
 *   - prediction-market/  Prediction-market conditional-token settlement
 */

export * from "./common";
export {
  applyAuthorization,
  type ScriptAuthorizer,
  type PlutusVersion,
} from "./authorization";

export * from "./vesting";
export * from "./prediction-market";

/**
 * Upgradeability: MeshJS off-chain submodule (the reusable part).
 *
 * The `counter_*` demo lives in `@contracts-library/meshjs/examples/upgradeability`.
 */

export * from "./types";
export { opaqueRedeemer, registryToData, registryFromUtxo } from "./datum";
export {
  addDelegateInvocation,
  buildRegistryApplyTx,
  buildRegistryProposeTx,
  readRegistry,
  type DelegateInvocationParams,
  type RegistryProposeParams,
} from "./upgradeability";

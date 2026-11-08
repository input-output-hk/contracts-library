/**
 * The upgradeability `counter_*` demo (non-normative): scripts, datums and
 * builders for the reference validators in `onchain/validators/upgradeability/`.
 * Import it as `@contracts-library/meshjs/examples/upgradeability`; the
 * reusable part is exported from the package root.
 */

export * from "./types";
export {
  counterDatumToData,
  counterDatumFromUtxo,
  steppedCounterDatumToData,
  steppedCounterFromUtxo,
  outputRefToData,
  tickRedeemer,
  upgradeRedeemer,
} from "./datum";
export {
  addressToData,
  counterScriptAddress,
  counterScriptHash,
  counterForwarderScript,
  counterLogicScript,
  counterLogicSteppedScript,
  counterV1Script,
  counterV2Script,
  counterMigrationScript,
  buildCounterTickTx,
  buildForwardMintTx,
  buildForwardTx,
  buildUpgradeTx,
  STATE_TOKEN_NAME as COUNTER_STATE_TOKEN_NAME,
  type TickTxParams,
  type ForwardMintTxParams,
  type ForwardTxParams,
  type UpgradeTxParams,
} from "./counter";
export {
  forwarderCompiledCode as counterForwarderCode,
  forwarderValidatorHash as counterForwarderValidatorHash,
  logicCompiledCode as counterLogicCode,
  logicValidatorHash as counterLogicValidatorHash,
  logicSteppedCompiledCode as counterLogicSteppedCode,
  logicSteppedValidatorHash as counterLogicSteppedValidatorHash,
  v1CompiledCode as counterV1Code,
  v1ValidatorHash as counterV1ValidatorHash,
  migrationCompiledCode as counterMigrationCode,
  migrationValidatorHash as counterMigrationValidatorHash,
  v2CompiledCode as counterV2Code,
  v2ValidatorHash as counterV2ValidatorHash,
  plutusVersion as counterPlutusVersion,
} from "./blueprint";

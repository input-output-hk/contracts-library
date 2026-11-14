/**
 * The upgradeability `counter_*` demo (non-normative): scripts, datums and
 * builders for the reference validators in `onchain/validators/upgradeability/`.
 * Import it as `@contracts-library/meshjs/examples/upgradeability`; the
 * reusable part is exported from the package root.
 */

export {
  forwarderCompiledCode as counterForwarderCode,
  forwarderValidatorHash as counterForwarderValidatorHash,
  logicCompiledCode as counterLogicCode,
  logicSteppedCompiledCode as counterLogicSteppedCode,
  logicSteppedValidatorHash as counterLogicSteppedValidatorHash,
  logicValidatorHash as counterLogicValidatorHash,
  migrationCompiledCode as counterMigrationCode,
  migrationValidatorHash as counterMigrationValidatorHash,
  plutusVersion as counterPlutusVersion,
  v1CompiledCode as counterV1Code,
  v1ValidatorHash as counterV1ValidatorHash,
  v2CompiledCode as counterV2Code,
  v2ValidatorHash as counterV2ValidatorHash,
} from "./blueprint";
export {
  addressToData,
  buildCounterTickTx,
  buildForwardMintTx,
  buildForwardTx,
  buildUpgradeTx,
  counterForwarderScript,
  counterLogicScript,
  counterLogicSteppedScript,
  counterMigrationScript,
  counterScriptAddress,
  counterScriptHash,
  counterV1Script,
  counterV2Script,
  type ForwardMintTxParams,
  type ForwardTxParams,
  STATE_TOKEN_NAME as COUNTER_STATE_TOKEN_NAME,
  type TickTxParams,
  type UpgradeTxParams,
} from "./counter";
export {
  counterDatumFromUtxo,
  counterDatumToData,
  outputRefToData,
  steppedCounterDatumToData,
  steppedCounterFromUtxo,
  tickRedeemer,
  upgradeRedeemer,
} from "./datum";
export * from "./types";

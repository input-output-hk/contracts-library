use cardano/assets.{AssetName, PolicyId}
use cardano/script_context.{ScriptContext}
use upgradeability/forward.{validate_forward}

/// Forced forwarder for the counter demo: holds the state and is the state
/// token's policy, and delegates every purpose to the registered logic.
validator counter_forwarder(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) {
  else(ctx: ScriptContext) {
    validate_forward(
      settings_policy,
      settings_token_name,
      ctx.info,
      ctx.transaction,
    )
  }
}

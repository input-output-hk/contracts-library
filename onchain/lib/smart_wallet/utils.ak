//// Smart wallet — read the `WalletConfig` from the settings UTxO.

use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Transaction}
use settings/utils.{get_settings_datum}
use smart_wallet/types.{WalletConfig}

/// Read the wallet config from the settings reference input (located by its NFT
/// under `settings_policy` / `settings_token_name`), casting the settings
/// contract's opaque `current` datum.
pub fn get_wallet_config(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) -> WalletConfig {
  let settings_datum = get_settings_datum(
    self,
    settings_policy,
    settings_token_name,
  )
  expect config: WalletConfig = settings_datum.current
  config
}

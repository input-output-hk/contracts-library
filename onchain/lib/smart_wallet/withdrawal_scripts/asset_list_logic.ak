//// Smart wallet — the `asset_allow_list` / `asset_deposit_allow_list` and
//// `asset_deny_list` / `asset_deposit_deny_list` withdrawal scripts' logic:
//// constrain which asset classes may move into or out of the wallet.
////
//// A class (policy, asset name) is *moving* when its quantity differs between
//// the wallet's summed value across the transaction inputs and across the
//// outputs; only the fact that it changed matters, not the magnitude, so
//// partial moves are caught. Ada is not a minted asset and is ignored, and the
//// wallet's own NFT (whose quantity is unchanged) is therefore never flagged.
////
//// The same checks serve both directions: delegated as a spender script they
//// gate assets leaving the wallet (`Spend`), and delegated as a depositor
//// script they gate assets entering it (`Deposit`).

use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId, Value, has_nft}
use cardano/transaction.{Output, Transaction}

/// Allow check: every asset class that moves must be authorised by `allowed`.
/// A policy listed with an empty name list allows any of its names; a policy
/// absent from the list allows none.
pub fn only_allowed_assets_moved(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
  allowed: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  let input = wallet_value(input_outputs(self), wallet, wallet_token_name)
  let output = wallet_value(self.outputs, wallet, wallet_token_name)
  classes_ok(input, output, allowed) && classes_ok(output, input, allowed)
}

/// Deny check: no asset class that moves may be listed in `denied`. A policy
/// listed with an empty name list denies all of its names; otherwise only the
/// listed names are denied.
pub fn no_denied_assets_moved(
  self: Transaction,
  wallet: Credential,
  wallet_token_name: AssetName,
  denied: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  let input = wallet_value(input_outputs(self), wallet, wallet_token_name)
  let output = wallet_value(self.outputs, wallet, wallet_token_name)
  classes_not_denied(input, output, denied) && classes_not_denied(
    output,
    input,
    denied,
  )
}

/// Every class of `side` whose quantity changed relative to `other` is allowed.
fn classes_ok(
  side: Value,
  other: Value,
  allowed: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  assets.reduce(
    assets.without_lovelace(side),
    True,
    fn(policy, name, quantity, ok) {
      ok && (
        assets.quantity_of(other, policy, name) == quantity || permitted(
          policy,
          name,
          allowed,
        )
      )
    },
  )
}

/// Every class of `side` whose quantity changed relative to `other` is not
/// denied.
fn classes_not_denied(
  side: Value,
  other: Value,
  denied: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  assets.reduce(
    assets.without_lovelace(side),
    True,
    fn(policy, name, quantity, ok) {
      ok && (
        assets.quantity_of(other, policy, name) == quantity || !denied_class(
          policy,
          name,
          denied,
        )
      )
    },
  )
}

fn permitted(
  policy: PolicyId,
  name: AssetName,
  allowed: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  when pairs.get_first(allowed, policy) is {
    None -> False
    Some(names) -> list.is_empty(names) || list.has(names, name)
  }
}

fn denied_class(
  policy: PolicyId,
  name: AssetName,
  denied: Pairs<PolicyId, List<AssetName>>,
) -> Bool {
  when pairs.get_first(denied, policy) is {
    None -> False
    Some(names) -> list.is_empty(names) || list.has(names, name)
  }
}

/// Sum of the values of NFT-bearing `outputs` sitting at the wallet's payment
/// credential.
fn wallet_value(
  outputs: List<Output>,
  wallet: Credential,
  wallet_token_name: AssetName,
) -> Value {
  expect Script(wallet_hash) = wallet
  list.foldl(
    outputs,
    assets.zero,
    fn(output, acc) {
      if output.address.payment_credential == wallet && has_nft(
        output.value,
        wallet_hash,
        wallet_token_name,
      ) {
        assets.merge(acc, output.value)
      } else {
        acc
      }
    },
  )
}

/// The outputs of the transaction's inputs (resolved outputs behind inputs).
fn input_outputs(self: Transaction) -> List<Output> {
  list.map(self.inputs, fn(input) { input.output })
}

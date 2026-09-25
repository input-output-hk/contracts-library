//// Reference validators for the smart wallet (see `docs/smart-wallet/design.typ`).
//// Thin wrappers over the reusable predicates in `lib/smart_wallet`:
//// `smart_wallet` is a multivalidator — a one-shot minting policy that creates
//// the wallet's identifying NFT, plus the spending script with its base M-of-N
//// floor — and `spending_limit` is an example delegated withdrawal script that
//// bounds the wallet's net outflow. Consumers may use these as-is or embed the
//// `checks` functions in their own validators.

use aiken/collection/list
use authorization
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace, PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use smart_wallet/checks
use smart_wallet/mint.{validate_burn, validate_mint}
use smart_wallet/types.{
  Burn, Close, Mint, MintRedeemer, Spend, SpendRedeemer, UpdateWithdrawals,
  WalletDatum,
}

/// Multivalidator for a smart wallet. A wallet UTxO is identified by the NFT
/// minted under this script's own policy (one-shot, via `seed_utxo`). Its datum
/// carries the delegated `withdrawals` list; the `admin` credential allowed to
/// change it is a script parameter. `Spend` releases funds when at least
/// `threshold` of `members` (read from the wallet configuration) sign **and**
/// every delegated withdrawal script in the datum is invoked.
/// `UpdateWithdrawals` lets the `admin` rewrite that list in place.
validator smart_wallet(
  seed_utxo: OutputReference,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  wallet_token_name: AssetName,
  admin: Credential,
) {
  spend(
    datum: Option<WalletDatum>,
    redeemer: SpendRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(wallet_datum) = datum
    expect Some(own_input) = find_input(self.inputs, own_ref)
    expect Script(own_hash) = own_input.output.address.payment_credential
    expect assets.has_nft(own_input.output.value, own_hash, wallet_token_name)
    when redeemer is {
      Spend ->
        checks.signed_m_of_n(self, settings_policy, settings_token_name) && checks.withdrawals_invoked(
          wallet_datum.withdrawals,
          self.withdrawals,
        )
      UpdateWithdrawals { out_ix } ->
        validate_withdrawals_update(admin, out_ix, own_ref, self)
      Close -> checks.validate_close(admin, own_ref, self)
    }
  }

  mint(redeemer: MintRedeemer, own_policy: PolicyId, self: Transaction) {
    when redeemer is {
      Mint { out_ix } ->
        validate_mint(
          seed_utxo,
          out_ix,
          own_policy,
          wallet_token_name,
          admin,
          self,
        )
      Burn -> validate_burn(own_policy, self)
    }
  }

  else(_) {
    fail
  }
}

/// Authorized rewrite of a wallet UTxO's `withdrawals` list: the script's
/// `admin` parameter must approve, and the continuation at `out_ix` must sit at
/// the same address with the same value — only `withdrawals` may change, so an
/// update cannot move funds.
fn validate_withdrawals_update(
  admin: Credential,
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect
    authorization.is_authorized(admin, self.extra_signatories, self.withdrawals)
  expect Some(own_input) = find_input(self.inputs, own_ref)
  expect Some(continuation) = list.at(self.outputs, out_ix)
  expect InlineDatum(raw) = continuation.datum
  expect _new_datum: WalletDatum = raw
  and {
    continuation.address == own_input.output.address,
    assets.match(continuation.value, own_input.output.value, >=),
  }
}

/// Delegated spending-limit script (withdraw-0). Requires the wallet's net
/// outflow `input - output` to stay below `bound` lovelace.
validator spending_limit(wallet: Credential, bound: Lovelace) {
  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    checks.within_spending_limit(self, wallet, bound)
  }

  else(_) {
    fail
  }
}

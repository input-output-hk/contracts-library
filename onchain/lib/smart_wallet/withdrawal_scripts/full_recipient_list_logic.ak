//// Smart wallet — the `full_recipient_allow_list` and
//// `full_recipient_block_list` withdrawal scripts' logic: constrain which
//// addresses may receive the wallet's funds.
////
//// Both checks match *full* addresses (payment and stake credential) and
//// exempt outputs at the wallet's payment credential, which stay under the
//// wallet's own control (e.g. the `Spend` continuation output).

use aiken/collection/list
use cardano/address.{Address, Credential}
use cardano/transaction.{Transaction}

/// Allow-list check: every payout address must be listed in `allowed` (an
/// empty list forbids any payout).
pub fn only_allowed_recipients(
  self: Transaction,
  wallet: Credential,
  allowed: List<Address>,
) -> Bool {
  payout_addresses(self, wallet)
    |> list.all(fn(address) { list.has(allowed, address) })
}

/// Block-list check: no payout address may be listed in `blocked` (an empty
/// list allows any payout).
pub fn no_blocked_recipients(
  self: Transaction,
  wallet: Credential,
  blocked: List<Address>,
) -> Bool {
  payout_addresses(self, wallet)
    |> list.all(fn(address) { !list.has(blocked, address) })
}

/// The full addresses of outputs that receive the wallet's funds: every output
/// whose payment credential differs from the wallet's.
fn payout_addresses(self: Transaction, wallet: Credential) -> List<Address> {
  list.filter_map(
    self.outputs,
    fn(output) {
      if output.address.payment_credential == wallet {
        None
      } else {
        Some(output.address)
      }
    },
  )
}

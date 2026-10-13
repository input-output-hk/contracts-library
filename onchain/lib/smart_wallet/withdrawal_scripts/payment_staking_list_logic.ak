//// Smart wallet — the `payment_staking_allow_list` and
//// `payment_staking_block_list` withdrawal scripts' logic: constrain which
//// payment and staking credentials may receive the wallet's funds.
////
//// Each payout address is checked on two independent dimensions: its payment
//// credential and its staking credential. A list left empty leaves its
//// dimension unrestricted. Staking credentials are compared only when given
//// inline; pointer staking credentials cannot be listed and count as absent.
//// Outputs at the wallet's payment credential are exempt — they stay under
//// the wallet's own control (e.g. the `Spend` continuation output).

use aiken/collection/list
use cardano/address.{Address, Credential, Inline}
use cardano/transaction.{Transaction}

/// Allow check: every payout address's payment credential must be listed in
/// `allowed_payments` (unless that list is empty) and its inline staking
/// credential in `allowed_stakings` (unless that list is empty). A payout
/// without an inline staking credential is rejected when `allowed_stakings`
/// is non-empty.
pub fn only_allowed_recipients(
  self: Transaction,
  wallet: Credential,
  allowed_payments: List<Credential>,
  allowed_stakings: List<Credential>,
) -> Bool {
  list.all(
    self.outputs,
    fn(output) {
      output.address.payment_credential == wallet || payment_permitted(
        output.address,
        allowed_payments,
      ) && staking_permitted(output.address, allowed_stakings)
    },
  )
}

/// Deny check: no payout address's payment credential may be listed in
/// `denied_payments` and no inline staking credential in `denied_stakings`
/// (each list left empty leaves its dimension unrestricted).
pub fn no_denied_recipients(
  self: Transaction,
  wallet: Credential,
  denied_payments: List<Credential>,
  denied_stakings: List<Credential>,
) -> Bool {
  list.all(
    self.outputs,
    fn(output) {
      output.address.payment_credential == wallet || !payment_denied(
        output.address,
        denied_payments,
      ) && !staking_denied(output.address, denied_stakings)
    },
  )
}

fn payment_permitted(address: Address, allowed: List<Credential>) -> Bool {
  list.is_empty(allowed) || list.has(allowed, address.payment_credential)
}

fn staking_permitted(address: Address, allowed: List<Credential>) -> Bool {
  when stake_credential(address) is {
    Some(credential) -> list.is_empty(allowed) || list.has(allowed, credential)
    None -> list.is_empty(allowed)
  }
}

fn payment_denied(address: Address, denied: List<Credential>) -> Bool {
  !list.is_empty(denied) && list.has(denied, address.payment_credential)
}

fn staking_denied(address: Address, denied: List<Credential>) -> Bool {
  when stake_credential(address) is {
    Some(credential) -> !list.is_empty(denied) && list.has(denied, credential)
    None -> False
  }
}

/// The staking credential of an address, when given inline. Pointer staking
/// credentials cannot be listed or compared and count as absent.
fn stake_credential(address: Address) -> Option<Credential> {
  when address.stake_credential is {
    Some(Inline(credential)) -> Some(credential)
    _ -> None
  }
}

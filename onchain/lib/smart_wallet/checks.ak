//// Smart wallet — reusable check functions.

use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{VerificationKeyHash}
use authorization
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace, PolicyId, Value}
use cardano/transaction.{Output, OutputReference, Transaction, find_input}
use smart_wallet/utils

/// Base M-of-N floor: reads the wallet config (members + threshold) from the
/// settings UTxO and asserts at least `threshold` of `members` signed. The
/// spending validator stays agnostic of how members and threshold are sourced.
pub fn signed_m_of_n(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) -> Bool {
  let config = utils.get_wallet_config(
    self,
    settings_policy,
    settings_token_name,
  )
  members_signed(config.members, config.threshold, self.extra_signatories)
}

/// Pure M-of-N predicate: at least `threshold` of `members` appear in
/// `extra_signatories`.
///
/// Signatures from non-members are ignored, and a member counts at most once
/// even if it appears twice in `extra_signatories`.
pub fn members_signed(
  members: List<VerificationKeyHash>,
  threshold: Int,
  extra_signatories: List<VerificationKeyHash>,
) -> Bool {
  let signed = list.count(
    members,
    fn(member) { list.has(extra_signatories, member) },
  )
  signed >= threshold
}

/// Spending-limit check: the net lovelace outflow `input - output` stays
/// strictly below `bound`.
///
/// `input` and `output` are the aggregate values a caller has summed over the
/// wallet's inputs and outputs; the delegated withdrawal script passes those in
/// and asserts the outflow is bounded.
pub fn value_delta_below_bound(
  input: Value,
  output: Value,
  bound: Lovelace,
) -> Bool {
  assets.lovelace_of(input) - assets.lovelace_of(output) < bound
}

/// Whole-transaction spending-limit check: sums the value on UTxOs at `wallet`
/// across the inputs and outputs and bounds the net outflow with
/// `value_delta_below_bound`.
pub fn within_spending_limit(
  self: Transaction,
  wallet: Credential,
  bound: Lovelace,
) -> Bool {
  let input = sum_at_credential(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  let output = sum_at_credential(self.outputs, wallet)
  value_delta_below_bound(input, output, bound)
}

/// Delegation check: every credential in `required` keys a reward withdrawal in
/// `withdrawals`, i.e. each delegated withdraw-0 script ran and approved. The
/// spend asserts this conjunction so no configured restriction can be omitted.
pub fn withdrawals_invoked(
  required: List<Credential>,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  list.all(required, fn(credential) { pairs.has_key(withdrawals, credential) })
}

/// Close check: the wallet's `admin` authorizes, and the wallet NFT (under the
/// spending script's own policy, read from the wallet UTxO at `own_ref`) is
/// burned in this transaction. Closing spends the wallet UTxO and destroys its
/// identifying NFT, releasing whatever funds remain.
pub fn validate_close(
  admin: Credential,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, mint, .. } = self
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential

  let burned = {
    expect [Pair(_, quantity)] = mint
      |> assets.tokens(own_hash)
      |> dict.to_pairs()
    quantity == -1
  }

  and {
    authorization.is_authorized(admin, self.extra_signatories, self.withdrawals),
    burned,
  }
}

/// Aggregate value across `outputs` whose payment credential is `credential`.
fn sum_at_credential(outputs: List<Output>, credential: Credential) -> Value {
  list.foldl(
    outputs,
    assets.zero,
    fn(output, acc) {
      if output.address.payment_credential == credential {
        assets.merge(acc, output.value)
      } else {
        acc
      }
    },
  )
}

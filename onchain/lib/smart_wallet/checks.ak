//// Smart wallet — reusable check functions.

use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use authorization
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, Lovelace, PolicyId, Value}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use smart_wallet/types.{WalletDatum}
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

/// Delegation check: every script in `required` keys a reward withdrawal in
/// `withdrawals`, i.e. each delegated withdraw-0 script ran and approved. The
/// spend asserts this conjunction so no configured restriction can be omitted.
pub fn withdrawals_invoked(
  required: Pairs<ScriptHash, Data>,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  list.all(
    pairs.keys(required),
    fn(script_hash) { pairs.has_key(withdrawals, Script(script_hash)) },
  )
}

/// Publication check: every script in `withdrawals` was published in this
/// transaction, i.e. its stake credential was registered via a
/// `RegisterCredential` certificate, which runs the script's `publish` handler.
/// The handler itself reads and validates its initial `Data` from the wallet
/// output's datum, so the wallet only asserts the registration here.
pub fn withdrawals_published(
  withdrawals: Pairs<ScriptHash, Data>,
  self: Transaction,
) -> Bool {
  list.all(withdrawals, fn(pair) { registered_in_tx(pair.1st, self) })
}

/// Update check: every script *added* by `new` (a hash absent from `old`) was
/// published in this transaction. Scripts present in `old` are assumed already
/// registered and are skipped here.
pub fn withdrawals_added_published(
  old: Pairs<ScriptHash, Data>,
  new: Pairs<ScriptHash, Data>,
  self: Transaction,
) -> Bool {
  list.all(
    new,
    fn(pair) {
      if pairs.has_key(old, pair.1st) {
        True
      } else {
        registered_in_tx(pair.1st, self)
      }
    },
  )
}

/// Update check: every script *removed* by `new` (a hash in `old` but not in
/// `new`) was unregistered via an `UnregisterCredential` certificate, freeing
/// its stake credential so it may be registered (and re-validated) again later.
pub fn withdrawals_removed_unregistered(
  old: Pairs<ScriptHash, Data>,
  new: Pairs<ScriptHash, Data>,
  self: Transaction,
) -> Bool {
  list.all(
    old,
    fn(pair) {
      if pairs.has_key(new, pair.1st) {
        True
      } else {
        list.any(
          self.certificates,
          fn(certificate) {
            when certificate is {
              UnregisterCredential { credential: Script(h), .. } ->
                h == pair.1st
              _ -> False
            }
          },
        )
      }
    },
  )
}

/// Update check: every script *kept* across the update (a hash in both `old`
/// and `new`) carries identical `Data`. Changing a script's data therefore
/// requires removing (unregistering) and re-adding (re-publishing) it.
pub fn withdrawals_kept_unchanged(
  old: Pairs<ScriptHash, Data>,
  new: Pairs<ScriptHash, Data>,
) -> Bool {
  list.all(
    new,
    fn(pair) {
      when pairs.get_first(old, pair.1st) is {
        Some(old_data) -> cbor.serialise(old_data) == cbor.serialise(pair.2nd)
        None -> True
      }
    },
  )
}

/// A single script was published in this transaction: a `RegisterCredential`
/// certificate for its stake credential, which runs the script's `publish`
/// handler. The handler reads and validates its own initial `Data` from the
/// wallet output's datum.
fn registered_in_tx(hash: ScriptHash, self: Transaction) -> Bool {
  list.any(
    self.certificates,
    fn(certificate) {
      when certificate is {
        RegisterCredential { credential: Script(h), .. } -> h == hash
        _ -> False
      }
    },
  )
}

/// The `Data` the wallet's output datum associates with `own_hash`, i.e. a
/// withdrawal script's own initial (or current) mutable state. Used by a
/// withdrawal script's `publish` handler to read and validate its initial
/// `Data` from the wallet UTxO.
pub fn own_withdrawal_data(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  let output = list.expect_find(
    self.outputs,
    fn(output) { output.address.payment_credential == wallet },
  )
  expect InlineDatum(raw) = output.datum
  expect wallet_datum: WalletDatum = raw
  expect Some(data) = pairs.get_first(wallet_datum.withdrawals, own_hash)
  data
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

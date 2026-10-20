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
  InlineDatum, OutputReference, Publish, Transaction, find_input,
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
/// `members` is treated as a set: a duplicate member counts once, and the
/// threshold must satisfy `0 < threshold <= distinct member count`. Signatures
/// from non-members are ignored, and a member counts at most once even if it
/// appears twice in `extra_signatories`.
pub fn members_signed(
  members: List<VerificationKeyHash>,
  threshold: Int,
  extra_signatories: List<VerificationKeyHash>,
) -> Bool {
  let unique_members = list.unique(members)
  let valid_threshold = threshold > 0 && threshold <= list.length(
    unique_members,
  )
  let signed = list.count(
    unique_members,
    fn(member) { list.has(extra_signatories, member) },
  )
  valid_threshold && signed >= threshold
}

/// Whether every key in a delegated-script map is unique. `same_keys` and
/// `withdrawals_equal` rely on key uniqueness to compare maps as sets.
pub fn keys_unique(scripts: Pairs<ScriptHash, Data>) -> Bool {
  let keys = pairs.keys(scripts)
  list.length(keys) == list.length(list.unique(keys))
}

/// Delegation check: every script in `required` keys a reward withdrawal in
/// `withdrawals`, i.e. each delegated withdraw-0 script ran and approved. The
/// spend and deposit paths assert this conjunction so no configured
/// authorization can be omitted.
pub fn withdrawals_invoked(
  required: Pairs<ScriptHash, Data>,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  list.all(
    pairs.keys(required),
    fn(script_hash) { pairs.has_key(withdrawals, Script(script_hash)) },
  )
}

/// Publication check: every script in `scripts` was published in this
/// transaction. That requires both a `RegisterCredential` certificate for its
/// stake credential and the matching `Publish` redeemer (the CIP-69 script
/// witness), so the script's `publish` handler actually ran and validated its
/// initial `Data`. A bare certificate — notably a legacy registration that needs
/// no witness — is not enough.
pub fn withdrawals_published(
  scripts: Pairs<ScriptHash, Data>,
  self: Transaction,
) -> Bool {
  list.all(scripts, fn(pair) { published_in_tx(pair.1st, self) })
}

/// Update check: every script *added* by `new` (a hash absent from `old`) was
/// published in this transaction, i.e. registered **and** witnessed by its
/// matching `Publish` redeemer. Scripts present in `old` are assumed already
/// published and are skipped here.
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
        published_in_tx(pair.1st, self)
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

/// A single script was published in this transaction: its stake credential was
/// registered via a `RegisterCredential` certificate **and** the transaction
/// carries a matching `Publish` redeemer at that certificate's index. The
/// redeemer is the CIP-69 script witness, so its presence proves the script's
/// `publish` handler ran; a legacy registration certificate has no such
/// redeemer.
fn published_in_tx(hash: ScriptHash, self: Transaction) -> Bool {
  list.any(
    self.redeemers,
    fn(redeemer) {
      when redeemer.1st is {
        Publish { at, certificate } ->
          when certificate is {
            RegisterCredential { credential: Script(h), .. } ->
              h == hash && when list.at(self.certificates, at) is {
                Some(RegisterCredential { credential: Script(cert_hash), .. }) ->
                  cert_hash == hash
                _ -> False
              }
            _ -> False
          }
        _ -> False
      }
    },
  )
}

/// Spend check: the wallet survives the spend with its permission set intact
/// and without gaining value. `depositors` is immutable across a spend (only
/// `UpdatePermissions` may change the map), the `spenders` key set is fixed
/// (only `UpdatePermissions` may add or remove delegated scripts), and the
/// continuation's value is a subset of the input's — a spend only removes value;
/// additions belong to `Deposit`. The transaction must recreate the wallet: an
/// NFT-bearing output at the wallet's payment credential carrying an inline
/// `WalletDatum` meeting those conditions. Any other output at the wallet's
/// payment credential is rejected: without the NFT it could never be spent and
/// would permanently lock funds. Spender `Data` may change: each spender script
/// enforces its own transition.
pub fn validate_spend_continuation(
  old_datum: WalletDatum,
  old_value: Value,
  wallet_policy: PolicyId,
  wallet_token_name: AssetName,
  self: Transaction,
) -> Bool {
  let wallet_outputs = list.filter(
    self.outputs,
    fn(output) { output.address.payment_credential == Script(wallet_policy) },
  )
  let continuations = list.filter(
    wallet_outputs,
    fn(output) {
      assets.has_nft(output.value, wallet_policy, wallet_token_name)
    },
  )
  !list.is_empty(continuations) && list.length(wallet_outputs) == list.length(
    continuations,
  ) && list.all(
    continuations,
    fn(output) {
      expect InlineDatum(raw) = output.datum
      expect new_datum: WalletDatum = raw
      and {
        keys_unique(new_datum.spenders),
        keys_unique(new_datum.depositors),
        withdrawals_equal(old_datum.depositors, new_datum.depositors),
        same_keys(old_datum.spenders, new_datum.spenders),
        value_contains(old_value, output.value),
      }
    },
  )
}

/// Close check: the wallet's `admin` authorizes, and the wallet NFT (under the
/// spending script's own policy, read from the wallet UTxO at `own_ref`) is
/// burned in this transaction. Closing spends the wallet UTxO and destroys its
/// identifying NFT, releasing whatever funds remain, and unregisters every
/// delegated script (`spenders` and `depositors`) so their stake deposits are
/// refunded.
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

  expect InlineDatum(raw) = own_input.output.datum
  expect datum: WalletDatum = raw

  and {
    authorization.is_authorized(admin, self.extra_signatories, self.withdrawals),
    burned,
    withdrawals_removed_unregistered(datum.spenders, [], self),
    withdrawals_removed_unregistered(datum.depositors, [], self),
  }
}

/// Deposit check: every script in the wallet's `depositors` map is invoked as a
/// reward withdrawal and approves, and the continuation at `out_ix` sits at the
/// same address with at least as much value (any asset, including lovelace and
/// the wallet NFT). A deposit preserves `spenders` and the `depositors` key set
/// (both are `UpdatePermissions`-only), while depositor `Data` may advance —
/// each deposit script enforces its own transition. A deposit can only add
/// funds, never spend them or change the permission set. With an empty
/// `depositors` map, a deposit needs no approval.
pub fn validate_deposit(
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect Some(own_input) = find_input(self.inputs, own_ref)
  expect InlineDatum(raw) = own_input.output.datum
  expect datum: WalletDatum = raw

  expect Some(continuation) = list.at(self.outputs, out_ix)
  expect InlineDatum(cont_raw) = continuation.datum
  expect cont_datum: WalletDatum = cont_raw

  and {
    withdrawals_invoked(datum.depositors, self.withdrawals),
    continuation.address == own_input.output.address,
    keys_unique(cont_datum.spenders),
    keys_unique(cont_datum.depositors),
    withdrawals_equal(datum.spenders, cont_datum.spenders),
    same_keys(datum.depositors, cont_datum.depositors),
    value_contains(continuation.value, own_input.output.value),
  }
}

/// Two script maps have the same keys with the same `Data`.
fn withdrawals_equal(
  old: Pairs<ScriptHash, Data>,
  new: Pairs<ScriptHash, Data>,
) -> Bool {
  let old_keys = list.unique(pairs.keys(old))
  let new_keys = list.unique(pairs.keys(new))
  list.length(old_keys) == list.length(new_keys) && list.all(
    old_keys,
    fn(hash) {
      when pairs.get_first(old, hash) is {
        Some(old_data) ->
          when pairs.get_first(new, hash) is {
            Some(new_data) ->
              cbor.serialise(old_data) == cbor.serialise(new_data)
            None -> False
          }
        None -> False
      }
    },
  )
}

/// Two script maps have the same key set, regardless of order. Keys are unique,
/// so equal length plus containment is set equality.
fn same_keys(old: Pairs<ScriptHash, Data>, new: Pairs<ScriptHash, Data>) -> Bool {
  let old_keys = list.unique(pairs.keys(old))
  let new_keys = list.unique(pairs.keys(new))
  list.length(old_keys) == list.length(new_keys) && list.all(
    old_keys,
    fn(hash) { list.has(new_keys, hash) },
  )
}

/// `superset` holds at least as much of every asset (and lovelace) as `subset`.
/// Used both ways: a deposit's continuation must contain the input (`superset` =
/// continuation), and a spend's continuation must be contained by the input
/// (`subset` = continuation).
fn value_contains(superset: Value, subset: Value) -> Bool {
  list.all(
    assets.flatten(subset),
    fn(triple) {
      let (policy, asset, qty) = triple
      assets.quantity_of(superset, policy, asset) >= qty
    },
  )
}

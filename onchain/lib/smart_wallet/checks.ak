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
  expect Some(datum) = wallet_datum(self.outputs, wallet)
  expect Some(data) = pairs.get_first(datum.withdrawals, own_hash)
  data
}

/// Like [`own_withdrawal_data`](#own_withdrawal_data) but reads the wallet's
/// *input* datum (the wallet UTxO being spent), i.e. a withdrawal script's own
/// *current* mutable state before this transaction. Used by a stateful
/// withdrawal script's `withdraw` handler to read the state it is transitioning
/// from.
pub fn own_withdrawal_data_in(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Data {
  expect Some(datum) = wallet_datum(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  expect Some(data) = pairs.get_first(datum.withdrawals, own_hash)
  data
}

/// Whether `own_hash` is being *removed* in this transaction: it is listed in
/// the wallet's input datum but not in its output datum (or there is no wallet
/// output at all, as on `Close`). Used by a withdrawal script's `publish`
/// handler to accept unregistration only when the script is actually leaving a
/// wallet, so it cannot be unregistered out of band.
pub fn own_withdrawal_removed(
  self: Transaction,
  wallet: Credential,
  own_hash: ScriptHash,
) -> Bool {
  expect Some(input_datum) = wallet_datum(
    list.map(self.inputs, fn(input) { input.output }),
    wallet,
  )
  let in_input = pairs.has_key(input_datum.withdrawals, own_hash)
  let in_output = when wallet_datum(self.outputs, wallet) is {
    Some(output_datum) -> pairs.has_key(output_datum.withdrawals, own_hash)
    None -> False
  }
  in_input && !in_output
}

/// The wallet UTxO's datum at `wallet`, if present among `outputs`.
fn wallet_datum(
  outputs: List<Output>,
  wallet: Credential,
) -> Option<WalletDatum> {
  when
    list.find(
      outputs,
      fn(output) { output.address.payment_credential == wallet },
    )
  is {
    Some(output) -> {
      expect InlineDatum(raw) = output.datum
      expect datum: WalletDatum = raw
      Some(datum)
    }
    None -> None
  }
}

/// Close check: the wallet's `admin` authorizes, and the wallet NFT (under the
/// spending script's own policy, read from the wallet UTxO at `own_ref`) is
/// burned in this transaction. Closing spends the wallet UTxO and destroys its
/// identifying NFT, releasing whatever funds remain, and unregisters every
/// delegated withdrawal script so their stake deposits are refunded.
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
    withdrawals_removed_unregistered(datum.withdrawals, [], self),
  }
}

/// Deposit check: the wallet's `depositor` authorizes, and the continuation at
/// `out_ix` sits at the same address carrying the wallet's unchanged datum with
/// at least as much value (any asset, including lovelace and the wallet NFT).
/// A deposit can only add funds, never spend them or alter the wallet's config.
pub fn validate_deposit(
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect Some(own_input) = find_input(self.inputs, own_ref)
  expect InlineDatum(raw) = own_input.output.datum
  expect datum: WalletDatum = raw

  expect
    authorization.is_authorized(
      datum.depositor,
      self.extra_signatories,
      self.withdrawals,
    )

  expect Some(continuation) = list.at(self.outputs, out_ix)
  expect InlineDatum(cont_raw) = continuation.datum
  expect cont_datum: WalletDatum = cont_raw

  and {
    continuation.address == own_input.output.address,
    datum_unchanged(datum, cont_datum),
    value_superset(continuation.value, own_input.output.value),
  }
}

/// Two wallet datums carry the same config: identical `depositor` and identical
/// `withdrawals` map (same keys, same `Data`).
fn datum_unchanged(old: WalletDatum, new: WalletDatum) -> Bool {
  old.depositor == new.depositor && withdrawals_equal(
    old.withdrawals,
    new.withdrawals,
  )
}

/// Two `withdrawals` maps have the same keys with the same `Data`.
fn withdrawals_equal(
  old: Pairs<ScriptHash, Data>,
  new: Pairs<ScriptHash, Data>,
) -> Bool {
  list.length(old) == list.length(new) && list.all(
    old,
    fn(pair) {
      when pairs.get_first(new, pair.1st) is {
        Some(new_data) -> cbor.serialise(pair.2nd) == cbor.serialise(new_data)
        None -> False
      }
    },
  )
}

/// `cont` holds at least as much of every asset (and lovelace) as `input`, i.e.
/// a deposit may add value but never remove any.
fn value_superset(cont: Value, input: Value) -> Bool {
  list.all(
    assets.flatten(input),
    fn(triple) {
      let (policy, asset, qty) = triple
      assets.quantity_of(cont, policy, asset) >= qty
    },
  )
}

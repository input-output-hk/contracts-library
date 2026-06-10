//// Reusable CIP-68 validation logic.
////
//// This module holds the pure predicate functions that a deployable validator
//// wires together. They follow the library's composability principles: each
//// function asserts only about the tokens it controls (the reference NFT and
//// its paired user token), the authorisation of the action, and the related
//// outputs — never about unrelated inputs/outputs or global transaction shape.

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{Input, InlineDatum, Output, OutputReference,
  Transaction}
use cip68/labels
use cip68/types.{Cip68Datum}

// ## Minting

/// Validate the minting of a CIP-68 pair.
///
/// Enforces:
/// 1. **Uniqueness** — the `seed` output reference is spent, making the policy
///    id one-shot (and thus unique to this issuance).
/// 2. **Pairing** — under this policy the transaction mints exactly one
///    reference NFT (label `100`, quantity `1`) and one user token (a user
///    label, quantity `>= 1`) sharing the same inner name.
/// 3. **Custody** — the reference NFT is sent to an output guarded by *this same
///    script* (payment credential `== own_policy`), carrying a valid inline
///    `Cip68Datum`.
pub fn mint_pair(
  self: Transaction,
  own_policy: PolicyId,
  seed: OutputReference,
) -> Bool {
  // (1) one-shot: the seed UTxO must be consumed.
  expect Some(_) = transaction.find_input(self.inputs, seed)

  // (2) pairing: exactly one reference NFT and one user token of this policy.
  expect [Pair(name_a, amount_a), Pair(name_b, amount_b)] =
    self.mint |> assets.tokens(own_policy) |> dict.to_pairs()

  expect Some((reference_name, reference_amount, _user_name, user_amount)) =
    classify(name_a, amount_a, name_b, amount_b)

  // (3) custody: reference NFT continues to this script with a valid datum.
  let custodied =
    list.any(
      transaction.find_script_outputs(self.outputs, own_policy),
      fn(output) {
        and {
          assets.quantity_of(output.value, own_policy, reference_name) == 1,
          has_cip68_datum(output),
        }
      },
    )

  and {
    reference_amount == 1,
    user_amount >= 1,
    custodied,
  }
}

/// Validate a burn under the minting policy: every quantity minted by this
/// policy must be negative. The tighter pairing rules for burning the reference
/// NFT are enforced by the spending validator when its UTxO is consumed.
pub fn burn(self: Transaction, own_policy: PolicyId) -> Bool {
  self.mint
    |> assets.tokens(own_policy)
    |> dict.to_pairs()
    |> list.all(fn(entry) { entry.2nd < 0 })
}

// ## Spending (reference NFT custody)

/// Validate an in-place metadata update.
///
/// The reference NFT must continue to the same script credential with a valid
/// `Cip68Datum`, and the spend must be authorised by the paired user token
/// being present among the transaction inputs.
pub fn update(self: Transaction, own_ref: OutputReference) -> Bool {
  let own_input = transaction.resolve_input(self.inputs, own_ref)
  let (reference_policy, reference_name) =
    own_reference_nft(own_input.value)
  let own_credential = own_input.address.payment_credential

  // The reference NFT continues to the same script with a valid datum.
  let continues =
    list.any(
      self.outputs,
      fn(output) {
        and {
          output.address.payment_credential == own_credential,
          assets.quantity_of(output.value, reference_policy, reference_name) == 1,
          has_cip68_datum(output),
        }
      },
    )

  and {
    continues,
    authorized_by_user_token(self.inputs, reference_policy, reference_name),
  }
}

/// Validate burning the reference NFT together with its paired user token.
///
/// Mirrors the reference implementation: both tokens of this pair must be
/// burned (reference exactly `-1`, user `<= -1`), they must share a policy and
/// inner name, and the burned reference NFT must be the one held in this UTxO.
pub fn burn_pair(self: Transaction, own_ref: OutputReference) -> Bool {
  let own_input = transaction.resolve_input(self.inputs, own_ref)
  let (reference_policy, reference_name) =
    own_reference_nft(own_input.value)

  let burned = self.mint |> assets.tokens(reference_policy) |> dict.to_pairs()

  let reference_burned =
    list.any(
      burned,
      fn(entry) { entry.1st == reference_name && entry.2nd == -1 },
    )

  let user_burned =
    list.any(
      burned,
      fn(entry) {
        and {
          labels.is_pair(reference_name, entry.1st),
          entry.2nd <= -1,
        }
      },
    )

  and {
    reference_burned,
    user_burned,
  }
}

// ## Helpers

/// Sort two minted (name, amount) entries into a reference NFT and a user
/// token, returning `(reference_name, reference_amount, user_name, user_amount)`
/// when they form a valid CIP-68 pair (in either order).
fn classify(
  name_a: ByteArray,
  amount_a: Int,
  name_b: ByteArray,
  amount_b: Int,
) -> Option<(ByteArray, Int, ByteArray, Int)> {
  if labels.is_pair(name_a, name_b) {
    Some((name_a, amount_a, name_b, amount_b))
  } else if labels.is_pair(name_b, name_a) {
    Some((name_b, amount_b, name_a, amount_a))
  } else {
    None
  }
}

/// The single reference NFT (policy, name) held in a value. Fails if absent.
fn own_reference_nft(value: Value) -> (PolicyId, ByteArray) {
  expect Some((policy, name, _)) =
    value
      |> assets.flatten
      |> list.find(fn(token) { labels.is_reference(token.2nd) })
  (policy, name)
}

/// Is the paired user token present among `inputs` (i.e. being spent)?
fn authorized_by_user_token(
  inputs: List<Input>,
  reference_policy: PolicyId,
  reference_name: ByteArray,
) -> Bool {
  list.any(
    inputs,
    fn(input) {
      input.output.value
        |> assets.tokens(reference_policy)
        |> dict.to_pairs()
        |> list.any(
            fn(entry) {
              and {
                labels.is_pair(reference_name, entry.1st),
                entry.2nd >= 1,
              }
            },
          )
    },
  )
}

/// Does the output carry an inline datum that decodes as a `Cip68Datum`?
fn has_cip68_datum(output: Output) -> Bool {
  when output.datum is {
    InlineDatum(data) -> {
      expect _: Cip68Datum = data
      True
    }
    _ -> False
  }
}

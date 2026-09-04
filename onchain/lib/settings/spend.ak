use aiken/collection/dict
use aiken/interval.{Finite}
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName}
use cardano/transaction.{OutputReference, Transaction, find_input}
use settings/types.{SettingsDatum}
use settings/utils.{expect_continuation}

/// Validate a proposal to change settings.
///
pub fn validate_propose(
  auth: Credential,
  apply_delay: Int,
  datum: Option<SettingsDatum>,
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
  settings_token_name: AssetName,
  validate_datum: fn(Data) -> Bool,
) {
  let Transaction { inputs, outputs, validity_range, .. } = self

  expect Finite(now) = validity_range.lower_bound.bound_type

  expect Some(input_datum) = datum
  let SettingsDatum { current, .. } = input_datum

  let cont_datum = expect_continuation(
    inputs,
    outputs,
    own_ref,
    out_ix,
    settings_token_name,
  )

  let correct_datum = {
    expect cont_datum: SettingsDatum = cont_datum
    expect Some(next_data) = cont_datum.next
    expect Some(next_apply_time) = cont_datum.next_apply
    cont_datum.current == current && next_apply_time >= now + apply_delay && validate_datum(
      next_data,
    ) && next_data != current
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_datum,
  }
}

/// Validate applying a previously proposed setting.
///
pub fn validate_apply(
  auth: Credential,
  datum: Option<SettingsDatum>,
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
  settings_token_name: AssetName,
  validate_datum: fn(Data) -> Bool,
) {
  let Transaction { inputs, outputs, validity_range, .. } = self

  expect Finite(now) = validity_range.lower_bound.bound_type

  expect Some(input_datum) = datum
  let SettingsDatum { next, next_apply, .. } = input_datum

  expect Some(next_data) = next
  expect Some(next_apply_time) = next_apply
  let correct_apply_time = now >= next_apply_time

  let cont_datum = expect_continuation(
    inputs,
    outputs,
    own_ref,
    out_ix,
    settings_token_name,
  )

  let correct_datum = {
    expect cont_datum: SettingsDatum = cont_datum
    let expected_datum = SettingsDatum {
      current: next_data,
      next: None,
      next_apply: None,
    }
    cont_datum == expected_datum && validate_datum(next_data)
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_datum,
    correct_apply_time,
  }
}

/// Validate closing the settings contract by burning the NFT.
///
pub fn validate_close(
  auth: Credential,
  own_ref: OutputReference,
  self: Transaction,
) {
  let Transaction { inputs, mint, .. } = self
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential

  let correct_burn = {
    expect [Pair(_, quantity)] = mint
      |> assets.tokens(own_hash)
      |> dict.to_pairs()
    quantity < 0
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_burn,
  }
}

use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{Finite}
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, has_nft_strict}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use settings/types.{SettingsDatum}

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

  expect Some(cont_output) = list.at(outputs, out_ix)
  expect Some(own_input) = find_input(inputs, own_ref)

  expect Script(own_hash) = own_input.output.address.payment_credential

  // checks for continuation output
  expect Output {
    address: cont_addr,
    value,
    datum: InlineDatum(cont_datum),
    reference_script: None,
  } = cont_output

  let correct_addr = cont_addr == own_input.output.address

  let correct_value = has_nft_strict(value, own_hash, settings_token_name)

  let correct_datum = {
    expect cont_datum: SettingsDatum = cont_datum
    let expected_datum =
      SettingsDatum {
        current,
        next: cont_datum.next,
        next_apply: Some(now + apply_delay),
      }
    expect Some(next_data) = cont_datum.next
    cont_datum == expected_datum && validate_datum(next_data)
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_addr,
    correct_value,
    correct_datum,
  }
}

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

  expect Some(cont_output) = list.at(outputs, out_ix)
  expect Some(own_input) = find_input(inputs, own_ref)

  expect Script(own_hash) = own_input.output.address.payment_credential

  // checks for continuation output
  expect Output {
    address: cont_addr,
    value,
    datum: InlineDatum(cont_datum),
    reference_script: None,
  } = cont_output

  let correct_addr = cont_addr == own_input.output.address

  let correct_value = has_nft_strict(value, own_hash, settings_token_name)

  let correct_datum = {
    expect cont_datum: SettingsDatum = cont_datum
    let expected_datum =
      SettingsDatum { current: next_data, next: None, next_apply: None }
    cont_datum == expected_datum && validate_datum(next_data)
  }

  and {
    is_authorized(auth, self.extra_signatories, self.withdrawals),
    correct_addr,
    correct_value,
    correct_datum,
    correct_apply_time,
  }
}

pub fn validate_close(own_ref: OutputReference, self: Transaction) {
  let Transaction { inputs, mint, .. } = self
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential

  let correct_burn = {
    expect [Pair(_, quantity)] =
      mint
        |> assets.tokens(own_hash)
        |> dict.to_pairs()
    quantity < 0
  }
  correct_burn
}

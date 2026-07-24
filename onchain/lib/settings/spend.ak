use cardano/assets.{PolicyId, has_nft_strict}
use cardano/address.{Credential, Script}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction, find_input}
use aiken/collection/list
use authorization.{is_authorized}
use settings/types.{SettingsDatum}

pub fn validate_propose(
  auth: Credential,
  apply_delay: Int,
  out_ix: Int,
  own_ref: OutputReference,
  self: Transaction,
  validate_datum: fn(Data) -> Bool,
) {
  let Transaction { inputs, outputs, mint, .. } = self

  expect Some(cont_output) = list.at(outputs, out_ix)

  expect Some(own_in) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_in.output.address.payment_credential

  // checks for continuation output
  expect Output {
    address: cont_addr,
    value: value,
    datum: InlineDatum(datum),
    reference_script: None,
  } = cont_output

  True
}

pub fn validate_apply(
  _auth: Credential,
  _apply_delay: Int,
  _out_ix: Int,
  _own_ref: OutputReference,
  _self: Transaction,
  _validate_datum: fn(Data) -> Bool,
) {
  True
}

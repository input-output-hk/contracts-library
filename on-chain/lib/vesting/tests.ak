//// Integration tests for the linear-vesting validation logic.
////
//// Scenario: 100 tokens vest linearly over `[1000, 2000]` in 10 installments,
//// first unlock allowed from time 1000. At the midpoint (now = 1500), exactly
//// 50 tokens must remain locked.

use aiken/interval
use cardano/address
use cardano/assets
use cardano/transaction.{InlineDatum, Input, Output, OutputReference,
  Transaction}
use vesting/types.{VestingAsset, VestingDatum}
use vesting/validation

// ## Fixtures

const own_hash: ByteArray =
  #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"

const beneficiary_hash: ByteArray =
  #"abababababababababababababababababababababababababababab"

const vesting_policy: ByteArray =
  #"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"

const vesting_token: ByteArray = "VEST"

const own_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }

fn datum() -> VestingDatum {
  VestingDatum {
    beneficiary: address.from_verification_key(beneficiary_hash),
    vesting_asset: VestingAsset {
      policy_id: vesting_policy,
      asset_name: vesting_token,
    },
    total_vesting_qty: 100,
    vesting_period_start: 1000,
    vesting_period_end: 2000,
    first_unlock_possible_after: 1000,
    total_installments: 10,
  }
}

fn script_value(qty: Int) -> assets.Value {
  assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(vesting_policy, vesting_token, qty))
}

fn vesting_input(reference: OutputReference, qty: Int) -> Input {
  Input {
    output_reference: reference,
    output: Output {
      address: address.from_script(own_hash),
      value: script_value(qty),
      datum: InlineDatum(datum()),
      reference_script: None,
    },
  }
}

fn continuing_output(qty: Int, output_datum: VestingDatum) -> Output {
  Output {
    address: address.from_script(own_hash),
    value: script_value(qty),
    datum: InlineDatum(output_datum),
    reference_script: None,
  }
}

// ## Partial unlock

// Midpoint: 100 in, 50 must remain, beneficiary signs.
test partial_unlock_ok() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      outputs: [continuing_output(50, datum())],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  validation.partial_unlock(datum(), own_ref, tx)
}

// Withdrawing more than the schedule allows (leaving only 40) must fail.
test partial_unlock_takes_too_much() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      outputs: [continuing_output(40, datum())],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  !validation.partial_unlock(datum(), own_ref, tx)
}

// Missing beneficiary signature is unauthorised.
test partial_unlock_no_signature() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      outputs: [continuing_output(50, datum())],
      extra_signatories: [],
      validity_range: interval.after(1500),
    }
  !validation.partial_unlock(datum(), own_ref, tx)
}

// Tampering with the returned datum must fail.
test partial_unlock_datum_modified() {
  let tampered = VestingDatum { ..datum(), total_vesting_qty: 1 }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      outputs: [continuing_output(50, tampered)],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  !validation.partial_unlock(datum(), own_ref, tx)
}

// Before first_unlock_possible_after, no partial unlock is allowed.
test partial_unlock_too_early() {
  let early = VestingDatum { ..datum(), first_unlock_possible_after: 1600 }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      outputs: [continuing_output(50, early)],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  !validation.partial_unlock(early, own_ref, tx)
}

// Two script inputs => double-satisfaction guard trips.
test partial_unlock_double_satisfaction() {
  let other_ref =
    OutputReference {
      transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
      output_index: 0,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100), vesting_input(other_ref, 100)],
      outputs: [continuing_output(50, datum())],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  !validation.partial_unlock(datum(), own_ref, tx)
}

// ## Full unlock

// After the period ends, the beneficiary can take everything.
test full_unlock_ok() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(2500),
    }
  validation.full_unlock(datum(), tx)
}

// Before the period ends, full unlock is not allowed.
test full_unlock_too_early() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [vesting_input(own_ref, 100)],
      extra_signatories: [beneficiary_hash],
      validity_range: interval.after(1500),
    }
  !validation.full_unlock(datum(), tx)
}

// ## div_ceil

test div_ceil_examples() {
  and {
    validation.div_ceil(1000, 10) == 100,
    validation.div_ceil(500, 100) == 5,
    validation.div_ceil(501, 100) == 6,
    validation.div_ceil(0, 100) == 0,
  }
}

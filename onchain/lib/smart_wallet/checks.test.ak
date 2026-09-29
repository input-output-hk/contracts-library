use aiken/cbor
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{InlineDatum, Output, Transaction, placeholder}
use smart_wallet/checks.{
  members_signed, own_withdrawal_data, value_delta_below_bound,
  withdrawals_added_published, withdrawals_invoked, withdrawals_kept_unchanged,
  withdrawals_published, withdrawals_removed_unregistered,
}
use smart_wallet/types.{WalletDatum}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const c = #"33333333333333333333333333333333333333333333333333333333"

// ------------------------------------------------------------- members_signed

test m_of_n_met_above_threshold() {
  members_signed([a, b, c], 2, [a, c])
}

test m_of_n_met_exactly() {
  members_signed([a, b, c], 2, [a, b])
}

test m_of_n_below_threshold() fail {
  members_signed([a, b, c], 2, [a])
}

test m_of_n_ignores_non_members() {
  // `c` is not a member, so only `a` counts — enough for a threshold of 1.
  members_signed([a, b], 1, [a, c])
}

// ------------------------------------------------------- value_delta_below_bound

test delta_negative_below_bound() {
  // 130 in - 100 out = 30 outflow < 50.
  value_delta_below_bound(
    assets.from_lovelace(130),
    assets.from_lovelace(100),
    50,
  )
}

test delta_at_bound_rejected() fail {
  // 150 in - 100 out = 50, not strictly < 50.
  value_delta_below_bound(
    assets.from_lovelace(150),
    assets.from_lovelace(100),
    50,
  )
}

test delta_above_bound_rejected() fail {
  // 200 in - 100 out = 100, not < 50.
  value_delta_below_bound(
    assets.from_lovelace(200),
    assets.from_lovelace(100),
    50,
  )
}

// --------------------------------------------------------- withdrawals_invoked

test withdrawals_all_invoked() {
  let data: Data = 0
  withdrawals_invoked(
    [Pair(a, data), Pair(b, data)],
    [Pair(Script(a), 0), Pair(Script(b), 0)],
  )
}

test withdrawals_none_required() {
  withdrawals_invoked([], [])
}

test withdrawals_missing_one() fail {
  let data: Data = 0
  withdrawals_invoked([Pair(a, data), Pair(b, data)], [Pair(Script(a), 0)])
}

// -------------------------------------------------------- withdrawals_published

test withdrawals_published_empty() {
  withdrawals_published([], placeholder)
}

test withdrawals_published_all_present() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    certificates: [RegisterCredential { credential: Script(a), deposit: Never }],
  }
  withdrawals_published([Pair(a, data)], tx)
}

test withdrawals_published_missing() fail {
  let data: Data = 0
  withdrawals_published([Pair(a, data)], placeholder)
}

test withdrawals_published_wrong_certificate() fail {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    certificates: [RegisterCredential { credential: Script(b), deposit: Never }],
  }
  withdrawals_published([Pair(a, data)], tx)
}

// ------------------------------------------------ withdrawals_added_published

test added_published_requires_publish_for_new() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    certificates: [RegisterCredential { credential: Script(a), deposit: Never }],
  }
  withdrawals_added_published([], [Pair(a, data)], tx)
}

test added_published_skips_existing() {
  let data: Data = 0
  withdrawals_added_published([Pair(a, data)], [Pair(a, data)], placeholder)
}

test added_published_missing_publish() fail {
  let data: Data = 0
  withdrawals_added_published([], [Pair(a, data)], placeholder)
}

// ---------------------------------------- withdrawals_removed_unregistered

test removed_unregistered_requires_cert_for_removed() {
  let data: Data = 0
  let tx = Transaction {
    ..placeholder,
    certificates: [
      UnregisterCredential { credential: Script(a), refund: Never },
    ],
  }
  withdrawals_removed_unregistered([Pair(a, data)], [], tx)
}

test removed_unregistered_skips_kept() {
  let data: Data = 0
  withdrawals_removed_unregistered(
    [Pair(a, data)],
    [Pair(a, data)],
    placeholder,
  )
}

test removed_unregistered_missing_cert() fail {
  let data: Data = 0
  withdrawals_removed_unregistered([Pair(a, data)], [], placeholder)
}

// ----------------------------------------------- withdrawals_kept_unchanged

test kept_unchanged_matching_data() {
  let data: Data = 0
  withdrawals_kept_unchanged([Pair(a, data)], [Pair(a, data)])
}

test kept_unchanged_ignores_added() {
  let data: Data = 0
  withdrawals_kept_unchanged([], [Pair(a, data)])
}

test kept_unchanged_rejects_changed_data() fail {
  let old: Data = 0
  let new: Data = 1
  withdrawals_kept_unchanged([Pair(a, old)], [Pair(a, new)])
}

// ------------------------------------------------------ own_withdrawal_data

test own_data_read_from_wallet_output() {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { withdrawals: [Pair(a, data)] }),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  cbor.serialise(own_withdrawal_data(tx, Script(a), a)) == cbor.serialise(data)
}

test own_data_missing_script() fail {
  let data: Data = 0
  let output = Output {
    address: from_script(a),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { withdrawals: [Pair(b, data)] }),
    reference_script: None,
  }
  let tx = Transaction { ..placeholder, outputs: [output] }
  expect _: Data = own_withdrawal_data(tx, Script(a), a)
}

test own_data_missing_wallet_output() fail {
  expect _: Data = own_withdrawal_data(placeholder, Script(a), a)
}

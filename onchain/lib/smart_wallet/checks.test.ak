use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets.{Value}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  DatumHash, InlineDatum, NoDatum, Output, Transaction, placeholder,
}
use smart_wallet/checks.{
  members_signed, validate_spend_continuation, withdrawals_added_published,
  withdrawals_invoked, withdrawals_kept_unchanged, withdrawals_published,
  withdrawals_removed_unregistered,
}
use smart_wallet/types.{WalletDatum}

const a = #"11111111111111111111111111111111111111111111111111111111"

const b = #"22222222222222222222222222222222222222222222222222222222"

const c = #"33333333333333333333333333333333333333333333333333333333"

const wallet_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const other_policy = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const wallet_token = "WALLET"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

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

// ------------------------------------------------ validate_spend_continuation

fn wallet_datum(
  spenders: Pairs<ScriptHash, Data>,
  depositors: Pairs<ScriptHash, Data>,
) -> WalletDatum {
  WalletDatum { spenders, depositors }
}

fn wallet_value() -> Value {
  assets.from_lovelace(1_000_000) |> assets.add(wallet_policy, wallet_token, 1)
}

fn wallet_output(
  spenders: Pairs<ScriptHash, Data>,
  depositors: Pairs<ScriptHash, Data>,
) -> Output {
  wallet_output_with(wallet_value(), spenders, depositors)
}

fn wallet_output_with(
  value: Value,
  spenders: Pairs<ScriptHash, Data>,
  depositors: Pairs<ScriptHash, Data>,
) -> Output {
  Output {
    address: from_script(wallet_policy),
    value,
    datum: InlineDatum(wallet_datum(spenders, depositors)),
    reference_script: None,
  }
}

fn spend_continuation(
  old_datum: WalletDatum,
  old_value: Value,
  outputs: List<Output>,
) -> Bool {
  validate_spend_continuation(
    old_datum,
    old_value,
    wallet_policy,
    wallet_token,
    Transaction { ..placeholder, outputs },
  )
}

test spend_ok_with_unchanged_depositors() {
  let data: Data = 0
  spend_continuation(
    wallet_datum([], [Pair(a, data)]),
    wallet_value(),
    [wallet_output([], [Pair(a, data)])],
  )
}

test spend_ok_with_changed_spender_data() {
  let data: Data = 0
  let new_state: Data = 1
  spend_continuation(
    wallet_datum([Pair(a, data)], [Pair(b, data)]),
    wallet_value(),
    [wallet_output([Pair(a, new_state)], [Pair(b, data)])],
  )
}

test spend_ok_with_reordered_spenders() {
  let data: Data = 0
  spend_continuation(
    wallet_datum([Pair(a, data), Pair(b, data)], []),
    wallet_value(),
    [wallet_output([Pair(b, data), Pair(a, data)], [])],
  )
}

test spend_ok_when_continuation_value_decreases() {
  let data: Data = 0
  let cont_value = assets.from_lovelace(500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  spend_continuation(
    wallet_datum([], [Pair(a, data)]),
    wallet_value(),
    [wallet_output_with(cont_value, [], [Pair(a, data)])],
  )
}

test spend_rejects_added_spender() fail {
  let data: Data = 0
  spend_continuation(
    wallet_datum([Pair(a, data)], []),
    wallet_value(),
    [wallet_output([Pair(a, data), Pair(b, data)], [])],
  )
}

test spend_rejects_removed_spender() fail {
  let data: Data = 0
  spend_continuation(
    wallet_datum([Pair(a, data), Pair(b, data)], []),
    wallet_value(),
    [wallet_output([Pair(a, data)], [])],
  )
}

test spend_ignores_non_nft_outputs_at_wallet_address() {
  let data: Data = 0
  let extra = Output {
    address: from_script(wallet_policy),
    value: assets.from_lovelace(500_000),
    datum: NoDatum,
    reference_script: None,
  }
  spend_continuation(
    wallet_datum([], [Pair(a, data)]),
    wallet_value(),
    [wallet_output([], [Pair(a, data)]), extra],
  )
}

test spend_rejects_rewritten_depositors() fail {
  let old_data: Data = 0
  let new_data: Data = 1
  spend_continuation(
    wallet_datum([], [Pair(a, old_data)]),
    wallet_value(),
    [wallet_output([], [Pair(a, new_data)])],
  )
}

test spend_rejects_missing_wallet_continuation() fail {
  let data: Data = 0
  spend_continuation(wallet_datum([], [Pair(a, data)]), wallet_value(), [])
}

test spend_rejects_nft_sent_elsewhere() fail {
  let data: Data = 0
  let elsewhere = Output {
    address: from_script(other_policy),
    value: wallet_value(),
    datum: InlineDatum(wallet_datum([], [Pair(a, data)])),
    reference_script: None,
  }
  spend_continuation(
    wallet_datum([], [Pair(a, data)]),
    wallet_value(),
    [elsewhere],
  )
}

test spend_rejects_non_inline_continuation() fail {
  let data: Data = 0
  let output = Output {
    ..wallet_output([], [Pair(a, data)]),
    datum: DatumHash(tx_id),
  }
  spend_continuation(
    wallet_datum([], [Pair(a, data)]),
    wallet_value(),
    [output],
  )
}

test spend_rejects_continuation_increasing_lovelace() fail {
  let cont_value = assets.from_lovelace(1_500_000)
    |> assets.add(wallet_policy, wallet_token, 1)
  spend_continuation(
    wallet_datum([], []),
    wallet_value(),
    [wallet_output_with(cont_value, [], [])],
  )
}

test spend_rejects_continuation_gaining_asset() fail {
  let cont_value = wallet_value() |> assets.add(other_policy, "SOME", 5)
  spend_continuation(
    wallet_datum([], []),
    wallet_value(),
    [wallet_output_with(cont_value, [], [])],
  )
}

test spend_rejects_continuation_increasing_asset_quantity() fail {
  let in_value = wallet_value() |> assets.add(other_policy, "SOME", 3)
  let cont_value = wallet_value() |> assets.add(other_policy, "SOME", 5)
  spend_continuation(
    wallet_datum([], []),
    in_value,
    [wallet_output_with(cont_value, [], [])],
  )
}

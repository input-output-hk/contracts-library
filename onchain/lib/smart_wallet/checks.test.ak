use cardano/address.{Script}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction, placeholder}
use smart_wallet/checks.{
  members_signed, withdrawals_added_published, withdrawals_invoked,
  withdrawals_kept_unchanged, withdrawals_published,
  withdrawals_removed_unregistered,
}

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

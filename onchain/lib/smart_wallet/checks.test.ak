use cardano/address.{Script}
use cardano/assets
use smart_wallet/checks.{
  members_signed, value_delta_below_bound, withdrawals_invoked,
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
  withdrawals_invoked(
    [Script(a), Script(b)],
    [Pair(Script(a), 0), Pair(Script(b), 0)],
  )
}

test withdrawals_none_required() {
  withdrawals_invoked([], [])
}

test withdrawals_missing_one() fail {
  withdrawals_invoked([Script(a), Script(b)], [Pair(Script(a), 0)])
}

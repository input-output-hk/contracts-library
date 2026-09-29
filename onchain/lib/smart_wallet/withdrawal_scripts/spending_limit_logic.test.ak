use cardano/assets
use smart_wallet/withdrawal_scripts/spending_limit_logic.{
  value_delta_below_bound,
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

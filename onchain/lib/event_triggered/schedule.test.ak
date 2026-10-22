// Tests for the schedule and asset-name helpers (spec §3.2, §3.4).

use cardano/assets
use event_triggered/schedule

test step_name_round_trip() {
  and {
    schedule.step_of_name(schedule.step_name(0)) == Some(0),
    schedule.step_of_name(schedule.step_name(1)) == Some(1),
    schedule.step_of_name(schedule.step_name(255)) == Some(255),
  }
}

test step_of_name_rejects_non_step_names() {
  and {
    schedule.step_of_name(#"0001") == None,
    schedule.step_of_name(#"") == None,
    schedule.step_of_name("REF") == None,
  }
}

test amount_round_trip() {
  and {
    schedule.decode_amount(schedule.encode_amount(1040)) == Some(1040),
    schedule.decode_amount(schedule.encode_amount(0)) == Some(0),
  }
}

test decode_amount_rejects_non_canonical() {
  and {
    schedule.decode_amount("01124") == None,
    schedule.decode_amount("") == None,
    schedule.decode_amount("1a") == None,
    schedule.decode_amount("REF") == None,
  }
}

test amount_at_is_one_indexed() {
  let amounts = [1040, 1081, 1124, 1169]
  and {
    schedule.amount_at(amounts, 1) == Some(1040),
    schedule.amount_at(amounts, 4) == Some(1169),
    schedule.amount_at(amounts, 0) == None,
    schedule.amount_at(amounts, 5) == None,
    schedule.final_step(amounts) == 4,
  }
}

test total_burned_sums_negative_entries() {
  let cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let mint = assets.from_asset(cnt_policy, schedule.encode_amount(1000), -1)
    |> assets.merge(
        assets.from_asset(cnt_policy, schedule.encode_amount(50), -2),
      )
    |> assets.merge(
        assets.from_asset(cnt_policy, schedule.encode_amount(999), 1),
      )
  schedule.total_burned(mint, cnt_policy) == Some(1100)
}

test total_burned_fails_closed_on_non_canonical() {
  let cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let mint = assets.from_asset(cnt_policy, "01124", -1)
  schedule.total_burned(mint, cnt_policy) == None
}

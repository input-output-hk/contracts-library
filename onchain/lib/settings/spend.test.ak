use aiken/interval.{Interval, after, before, between}
use cardano/address.{VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use settings/spend.{validate_propose}
use settings/types.{SettingsDatum}

const settings_hash =
  #"11111111111111111111111111111111111111111111111111111111"

const proposer = #"22222222222222222222222222222222222222222222222222222222"

const token_name = "settings"

const apply_delay = 86_400_000

const own_ref =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }

fn settings_output(datum: SettingsDatum) -> Output {
  let datum_data: Data = datum
  Output {
    address: from_script(settings_hash),
    value: assets.from_lovelace(5_000_000)
      |> assets.add(settings_hash, token_name, 1),
    datum: InlineDatum(datum_data),
    reference_script: None,
  }
}

fn current_value() -> Data {
  let value: Data = 1
  value
}

fn next_value() -> Data {
  let value: Data = 2
  value
}

fn idle() -> SettingsDatum {
  SettingsDatum { current: current_value(), next: None, next_apply: None }
}

/// Propose `next = 2` with the given `next_apply`, under `validity_range`.
fn propose(validity_range: Interval, next_apply: Int) -> Bool {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      Input { output_reference: own_ref, output: settings_output(idle()) },
    ],
    outputs: [
      settings_output(
        SettingsDatum {
          current: current_value(),
          next: Some(next_value()),
          next_apply: Some(next_apply),
        },
      ),
    ],
    extra_signatories: [proposer],
    validity_range,
  }
  validate_propose(
    VerificationKey(proposer),
    apply_delay,
    Some(idle()),
    0,
    own_ref,
    tx,
    token_name,
    fn(_) { True },
  )
}

const upper = 1_000_000_000

test propose_accepts_next_apply_at_upper_bound_plus_delay() {
  propose(between(upper - 600_000, upper), upper + apply_delay)
}

test propose_accepts_without_lower_bound() {
  propose(before(upper), upper + apply_delay)
}

test propose_accepts_a_later_next_apply() {
  propose(before(upper), upper + apply_delay + 1)
}

test propose_rejects_next_apply_before_upper_bound_plus_delay() {
  !propose(before(upper), upper + apply_delay - 1)
}

/// The old exploit: anchoring on a backdated lower bound. With the anchor on
/// the upper bound, a `next_apply` computed from the lower bound is too early.
test propose_rejects_a_backdated_anchor() {
  let backdated = upper - 365 * apply_delay
  !propose(between(backdated, upper), backdated + apply_delay)
}

test propose_rejects_an_unbounded_validity_range() fail {
  propose(after(upper), upper + apply_delay)
}

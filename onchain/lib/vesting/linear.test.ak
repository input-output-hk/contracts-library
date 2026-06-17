use aiken/fuzz
use aiken/interval
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, Output, OutputReference, Transaction,
  placeholder,
}
use vesting/linear.{validate_cancel, validate_claim, vested_quantity}
use vesting/types.{VestedAsset, VestingDatum}

// ----------------------------------------------------------------- fixtures

const own_script = #"99999999999999999999999999999999999999999999999999999999"

const beneficiary_key =
  #"11111111111111111111111111111111111111111111111111111111"

const locker_key = #"44444444444444444444444444444444444444444444444444444444"

const auth_script = #"22222222222222222222222222222222222222222222222222222222"

const token_policy = #"33333333333333333333333333333333333333333333333333333333"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

// Single-asset (ada) schedule: 100 lovelace over [1000, 2000], recovery 3000.
fn datum() -> VestingDatum {
  VestingDatum {
    beneficiary: VerificationKey(beneficiary_key),
    locker: VerificationKey(locker_key),
    vesting: [VestedAsset { policy: "", name: "", total: 100 }],
    start_time: 1000,
    end_time: 2000,
    recovery_time: 3000,
  }
}

fn input_with(d: VestingDatum, value: Value, index: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(own_script),
      value,
      datum: InlineDatum(d),
      reference_script: None,
    },
  }
}

fn output_with(d: VestingDatum, value: Value) -> Output {
  Output {
    address: from_script(own_script),
    value,
    datum: InlineDatum(d),
    reference_script: None,
  }
}

fn claim_tx(
  now: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  signatories: List<ByteArray>,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs,
    outputs,
    validity_range: interval.after(now),
    extra_signatories: signatories,
  }
}

// ----------------------------------------------------- vested_quantity props

fn scenario() -> Fuzzer<(Int, Int, Int, Int)> {
  fuzz.int_between(0, 1_000_000_000)
    |> fuzz.and_then(
        fn(total) {
          fuzz.int_between(0, 1_000_000)
            |> fuzz.and_then(
                fn(start) {
                  fuzz.int_between(start + 1, start + 1_000_000)
                    |> fuzz.and_then(
                        fn(end) {
                          fuzz.int_between(start - 100, end + 100)
                            |> fuzz.map(fn(now) { (total, start, end, now) })
                        },
                      )
                },
              )
        },
      )
}

test prop_vested_within_bounds((total, start, end, now) via scenario()) {
  let v = vested_quantity(total, start, end, now)
  v >= 0 && v <= total
}

test prop_zero_at_or_before_start((total, start, end, _now) via scenario()) {
  vested_quantity(total, start, end, start) == 0 && vested_quantity(
    total,
    start,
    end,
    start - 1,
  ) == 0
}

test prop_full_at_or_after_end((total, start, end, _now) via scenario()) {
  vested_quantity(total, start, end, end) == total && vested_quantity(
    total,
    start,
    end,
    end + 1,
  ) == total
}

test prop_monotonic_non_decreasing((total, start, end, now) via scenario()) {
  vested_quantity(total, start, end, now) <= vested_quantity(
    total,
    start,
    end,
    now + 1,
  )
}

// ---------------------------------------------------------- happy-path claims

test partial_claim_ok() {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx =
    claim_tx(
      1500,
      [input],
      [output_with(datum(), assets.from_lovelace(50))],
      [beneficiary_key],
    )
  validate_claim(datum(), input.output, tx)
}

test full_claim_takes_everything() {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(2000, [input], [], [beneficiary_key])
  validate_claim(datum(), input.output, tx)
}

test claim_at_start_must_keep_all() {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx =
    claim_tx(
      1000,
      [input],
      [output_with(datum(), assets.from_lovelace(100))],
      [beneficiary_key],
    )
  validate_claim(datum(), input.output, tx)
}

test script_beneficiary_claim_ok() {
  let d = VestingDatum { ..datum(), beneficiary: Script(auth_script) }
  let input = input_with(d, assets.from_lovelace(100), 0)
  let tx =
    Transaction {
      ..placeholder,
      inputs: [input],
      outputs: [output_with(d, assets.from_lovelace(50))],
      validity_range: interval.after(1500),
      withdrawals: [Pair(Script(auth_script), 0)],
    }
  validate_claim(d, input.output, tx)
}

test multi_asset_partial_ok() {
  let d =
    VestingDatum {
      ..datum(),
      vesting: [
        VestedAsset { policy: "", name: "", total: 100 },
        VestedAsset { policy: token_policy, name: "TOKEN", total: 10 },
      ],
    }
  let locked =
    assets.from_lovelace(100)
      |> assets.merge(assets.from_asset(token_policy, "TOKEN", 10))
  let kept =
    assets.from_lovelace(50)
      |> assets.merge(assets.from_asset(token_policy, "TOKEN", 5))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1500, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test batched_distinct_instances_ok() {
  // Two DIFFERENT instances claimed in one tx. Each keeps its own continuation;
  // each validates independently (k = 1 per datum). Composable batching.
  let d_a = datum()
  let d_b = VestingDatum { ..datum(), recovery_time: 3001 }
  let in_a = input_with(d_a, assets.from_lovelace(100), 0)
  let in_b = input_with(d_b, assets.from_lovelace(100), 1)
  let tx =
    claim_tx(
      1500,
      [in_a, in_b],
      [
        output_with(d_a, assets.from_lovelace(50)),
        output_with(d_b, assets.from_lovelace(50)),
      ],
      [beneficiary_key],
    )
  validate_claim(d_a, in_a.output, tx) && validate_claim(d_b, in_b.output, tx)
}

// ----------------------------------------------------------- adversarial claims

test rejects_overclaim() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx =
    claim_tx(
      1500,
      [input],
      [output_with(datum(), assets.from_lovelace(40))],
      [beneficiary_key],
    )
  validate_claim(datum(), input.output, tx)
}

test rejects_without_authorization() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx =
    claim_tx(
      1500,
      [input],
      [output_with(datum(), assets.from_lovelace(50))],
      [],
    )
  validate_claim(datum(), input.output, tx)
}

test rejects_schedule_tampering() fail {
  let mutated = VestingDatum { ..datum(), end_time: 1100 }
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx =
    claim_tx(
      1500,
      [input],
      [output_with(mutated, assets.from_lovelace(50))],
      [beneficiary_key],
    )
  validate_claim(datum(), input.output, tx)
}

test rejects_shared_continuation() fail {
  // Two inputs with the SAME datum sharing ONE continuation of 50. With the
  // k * required aggregate (k = 2), the continuation must hold 100, so this is
  // rejected: a beneficiary cannot collapse duplicate instances to bypass the
  // schedule.
  let input0 = input_with(datum(), assets.from_lovelace(100), 0)
  let input1 = input_with(datum(), assets.from_lovelace(100), 1)
  let tx =
    claim_tx(
      1500,
      [input0, input1],
      [output_with(datum(), assets.from_lovelace(50))],
      [beneficiary_key],
    )
  validate_claim(datum(), input0.output, tx)
}

test rejects_datum_hash_input() fail {
  let input =
    Input {
      output_reference: OutputReference {
        transaction_id: tx_id,
        output_index: 0,
      },
      output: Output {
        address: from_script(own_script),
        value: assets.from_lovelace(100),
        datum: DatumHash(tx_id),
        reference_script: None,
      },
    }
  let tx = claim_tx(2000, [input], [], [beneficiary_key])
  validate_claim(datum(), input.output, tx)
}

test rejects_multi_asset_token_shortfall() fail {
  let d =
    VestingDatum {
      ..datum(),
      vesting: [
        VestedAsset { policy: "", name: "", total: 100 },
        VestedAsset { policy: token_policy, name: "TOKEN", total: 10 },
      ],
    }
  let locked =
    assets.from_lovelace(100)
      |> assets.merge(assets.from_asset(token_policy, "TOKEN", 10))
  let kept =
    assets.from_lovelace(50)
      |> assets.merge(assets.from_asset(token_policy, "TOKEN", 4))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1500, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

// --------------------------------------------------------------------- cancel

test cancel_after_recovery_ok() {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(3001, [input], [], [locker_key])
  validate_cancel(datum(), tx)
}

test rejects_cancel_before_recovery() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(2999, [input], [], [locker_key])
  validate_cancel(datum(), tx)
}

test rejects_cancel_by_non_locker() fail {
  // The beneficiary cannot cancel; only the locker credential satisfies it.
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(3000, [input], [], [beneficiary_key])
  validate_cancel(datum(), tx)
}

test rejects_cancel_with_recovery_not_after_end() fail {
  // A malformed datum with recovery_time <= end_time must not allow early
  // recovery of unvested funds.
  let d = VestingDatum { ..datum(), recovery_time: 1500 }
  let input = input_with(d, assets.from_lovelace(100), 0)
  let tx = claim_tx(1500, [input], [], [locker_key])
  validate_cancel(d, tx)
}

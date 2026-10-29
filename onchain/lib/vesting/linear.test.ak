use aiken/collection/list
use aiken/fuzz
use aiken/interval
use cardano/address.{Credential, Script, VerificationKey, from_script}
use cardano/assets.{Lovelace, Value}
use cardano/fuzz as cardano_fuzz
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
  let tx = claim_tx(
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
  let tx = claim_tx(
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
  let tx = Transaction {
    ..placeholder,
    inputs: [input],
    outputs: [output_with(d, assets.from_lovelace(50))],
    validity_range: interval.after(1500),
    withdrawals: [Pair(Script(auth_script), 0)],
  }
  validate_claim(d, input.output, tx)
}

test multi_asset_partial_ok() {
  let d = VestingDatum {
    ..datum(),
    vesting: [
      VestedAsset { policy: "", name: "", total: 100 },
      VestedAsset { policy: token_policy, name: "TOKEN", total: 10 },
    ],
  }
  let locked = assets.from_lovelace(100)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 10))
  let kept = assets.from_lovelace(50)
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
  let tx = claim_tx(
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
  let tx = claim_tx(
    1500,
    [input],
    [output_with(datum(), assets.from_lovelace(40))],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

test rejects_without_authorization() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(
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
  let tx = claim_tx(
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
  let tx = claim_tx(
    1500,
    [input0, input1],
    [output_with(datum(), assets.from_lovelace(50))],
    [beneficiary_key],
  )
  validate_claim(datum(), input0.output, tx)
}

test rejects_datum_hash_input() fail {
  let input = Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 0 },
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
  let d = VestingDatum {
    ..datum(),
    vesting: [
      VestedAsset { policy: "", name: "", total: 100 },
      VestedAsset { policy: token_policy, name: "TOKEN", total: 10 },
    ],
  }
  let locked = assets.from_lovelace(100)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 10))
  let kept = assets.from_lovelace(50)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 4))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1500, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

// -------------------------------------------- instance-count preservation (§5.1)
//
// Regression guard for the cross-transaction instance-merge over-release.
//
// Setup: two identical instances, each datum total=100, each holding 100 lovelace
// (200 locked total). Schedule [1000, 2000]; at now=1500, vested(100)=50 each, so
// the honest amount claimable across BOTH instances is 100.
//
// The attack was a two-step drain: (1) spend both inputs into a SINGLE continuation
// of 100 — accepted under the old aggregate `k * required` rule — collapsing two
// instances into one UTxO whose datum still says total=100; then (2) spend that
// merged UTxO alone, where k has dropped to 1, so only 50 must stay and the other
// 50 is swept as "surplus". Net: 150 pulled at now=1500 against 100 vested.
//
// The fix (option 1) requires >= k SEPARATE continuations, each holding the full
// remainder, so step (1) can no longer concentrate the two instances. k can never
// drop below the number of live instances, and the drain is impossible.

test rejects_instance_merge() fail {
  // Two identical inputs collapsed into ONE continuation of 100. Rejected: with
  // k=2 the tx must carry >= 2 continuations, not 1.
  let input0 = input_with(datum(), assets.from_lovelace(100), 0)
  let input1 = input_with(datum(), assets.from_lovelace(100), 1)
  let tx = claim_tx(
    1500,
    [input0, input1],
    [output_with(datum(), assets.from_lovelace(100))],
    [beneficiary_key],
  )
  validate_claim(datum(), input0.output, tx)
}

test identical_instances_keep_separate_continuations_ok() {
  // The honest shape: two identical instances stay as two continuations, each
  // holding its own remainder (50). Batching identical instances still works;
  // only collapsing them into fewer UTxOs is forbidden.
  let input0 = input_with(datum(), assets.from_lovelace(100), 0)
  let input1 = input_with(datum(), assets.from_lovelace(100), 1)
  let tx = claim_tx(
    1500,
    [input0, input1],
    [
      output_with(datum(), assets.from_lovelace(50)),
      output_with(datum(), assets.from_lovelace(50)),
    ],
    [beneficiary_key],
  )
  validate_claim(datum(), input0.output, tx) && validate_claim(
    datum(),
    input1.output,
    tx,
  )
}

// ------------------------------------------------ end_time continuation boundary
//
// The continuation gate is `now >= end_time` (spec §8.2), not `now > end_time`.
// These two tests pin that boundary from both sides.

test full_claim_at_end_boundary_needs_no_continuation() {
  // now == end_time: everything has vested, so even k=2 identical inputs can be
  // fully claimed with NO continuation. A strict `>` gate would wrongly demand
  // continuations at exactly end_time and reject this.
  let input0 = input_with(datum(), assets.from_lovelace(100), 0)
  let input1 = input_with(datum(), assets.from_lovelace(100), 1)
  let tx = claim_tx(2000, [input0, input1], [], [beneficiary_key])
  validate_claim(datum(), input0.output, tx) && validate_claim(
    datum(),
    input1.output,
    tx,
  )
}

test rejects_no_continuation_just_before_end() fail {
  // now == end_time - 1: required is tiny (1) but non-zero, so a claim with NO
  // continuation must still be rejected. Complements the boundary test above.
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(1999, [input], [], [beneficiary_key])
  validate_claim(datum(), input.output, tx)
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

// --------------------------------------------------------------- properties

const token_name = "TOKEN"

fn authorize(
  credential: Credential,
) -> (List<ByteArray>, Pairs<Credential, Lovelace>) {
  when credential is {
    VerificationKey(hash) -> ([hash], [])
    Script(hash) -> ([], [Pair(Script(hash), 0)])
  }
}

test prop_claim_authorized_credential(credential via cardano_fuzz.credential()) {
  let d = VestingDatum { ..datum(), beneficiary: credential }
  let input = input_with(d, assets.from_lovelace(100), 0)
  let output = output_with(d, assets.from_lovelace(50))
  let (signers, withdrawals) = authorize(credential)
  let tx = Transaction {
    ..placeholder,
    inputs: [input],
    outputs: [output],
    validity_range: interval.after(1500),
    extra_signatories: signers,
    withdrawals,
  }
  validate_claim(d, input.output, tx)
}

test prop_claim_rejects_missing_authorization(
  credential via cardano_fuzz.credential(),
) fail {
  let d = VestingDatum { ..datum(), beneficiary: credential }
  let input = input_with(d, assets.from_lovelace(100), 0)
  let output = output_with(d, assets.from_lovelace(50))
  let tx = Transaction {
    ..placeholder,
    inputs: [input],
    outputs: [output],
    validity_range: interval.after(1500),
  }
  validate_claim(d, input.output, tx)
}

fn multi_datum(ada_total: Int, token_total: Int) -> VestingDatum {
  VestingDatum {
    ..datum(),
    vesting: [
      VestedAsset { policy: "", name: "", total: ada_total },
      VestedAsset { policy: token_policy, name: token_name, total: token_total },
    ],
  }
}

fn multi_value(ada: Int, token: Int) -> Value {
  assets.from_lovelace(ada) |> assets.add(token_policy, token_name, token)
}

fn conservation_scenario() -> Fuzzer<(Int, Int, Int)> {
  fuzz.tuple3(
    fuzz.int_between(1, 1_000),
    fuzz.int_between(1, 1_000),
    fuzz.int_between(1000, 1999),
  )
}

test prop_claim_multi_asset_conservation(
  (ada_total, token_total, at) via conservation_scenario(),
) {
  let d = multi_datum(ada_total, token_total)
  let required_ada = ada_total - vested_quantity(ada_total, 1000, 2000, at)
  let required_token = token_total - vested_quantity(
    token_total,
    1000,
    2000,
    at,
  )
  let input = input_with(d, multi_value(ada_total, token_total), 0)
  let output = output_with(d, multi_value(required_ada, required_token))
  let tx = claim_tx(at, [input], [output], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test prop_claim_multi_asset_shortfall(
  (ada_total, token_total, at) via conservation_scenario(),
) {
  let d = multi_datum(ada_total, token_total)
  let required_ada = ada_total - vested_quantity(ada_total, 1000, 2000, at)
  let required_token = token_total - vested_quantity(
    token_total,
    1000,
    2000,
    at,
  )
  let input = input_with(d, multi_value(ada_total, token_total), 0)
  let output = output_with(d, multi_value(required_ada, required_token - 1))
  let tx = claim_tx(at, [input], [output], [beneficiary_key])
  !validate_claim(d, input.output, tx)
}

fn cancel_scenario() -> Fuzzer<(Int, Int)> {
  fuzz.tuple(fuzz.int_between(1, 1_000_000), fuzz.int_between(0, 2_000_000))
}

test prop_cancel_strictly_after_recovery(
  (recovery_extra, at) via cancel_scenario(),
) {
  let recovery = 2000 + recovery_extra
  let d = VestingDatum { ..datum(), recovery_time: recovery }
  let input = input_with(d, assets.from_lovelace(100), 0)
  let tx = claim_tx(at, [input], [], [locker_key])
  let expected = at > recovery
  fuzz.label_if(@"after", expected)
  fuzz.label_if(@"not-after", !expected)
  validate_cancel(d, tx) == expected
}

fn k_scenario() -> Fuzzer<Int> {
  fuzz.int_between(1, 4)
}

test prop_identical_instances_need_k_continuations(k via k_scenario()) {
  let d = datum()
  let required = 50
  let inputs = list.map(
    list.range(0, k - 1),
    fn(i) { input_with(d, assets.from_lovelace(100), i) },
  )
  let outputs = list.map(
    list.range(0, k - 1),
    fn(_) { output_with(d, assets.from_lovelace(required)) },
  )
  let tx = claim_tx(1500, inputs, outputs, [beneficiary_key])
  list.all(inputs, fn(input) { validate_claim(d, input.output, tx) })
}

test prop_identical_instances_reject_fewer_continuations(k via k_scenario()) {
  let d = datum()
  let required = 50
  let inputs = list.map(
    list.range(0, k - 1),
    fn(i) { input_with(d, assets.from_lovelace(100), i) },
  )
  let outputs = if k > 1 {
    list.map(
      list.range(0, k - 2),
      fn(_) { output_with(d, assets.from_lovelace(required)) },
    )
  } else {
    []
  }
  let tx = claim_tx(1500, inputs, outputs, [beneficiary_key])
  list.all(inputs, fn(input) { !validate_claim(d, input.output, tx) })
}

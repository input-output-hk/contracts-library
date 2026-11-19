use aiken/fuzz
use aiken/interval
use cardano/address.{
  Address, Script, VerificationKey, from_script, with_delegation_key,
}
use cardano/assets.{Value}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, Output, OutputReference, Transaction,
  placeholder,
}
use vesting/linear.{
  bundle_well_formed, validate_cancel, validate_claim, vested_quantity,
}
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

// ------------------------------------------------- bundle well-formedness (§3.1)
//
// The `vesting` list must have strictly ascending `(policy, name)` keys and
// non-negative totals. A malformed bundle is rejected on `Claim` (fail closed)
// but never blocks `Cancel`, so the locker can always recover it.

const other_policy = #"55555555555555555555555555555555555555555555555555555555"

test bundle_empty_ok() {
  bundle_well_formed([])
}

test bundle_sorted_ok() {
  bundle_well_formed(
    [
      VestedAsset { policy: "", name: "", total: 100 },
      VestedAsset { policy: token_policy, name: "A", total: 1 },
      VestedAsset { policy: token_policy, name: "B", total: 0 },
      VestedAsset { policy: other_policy, name: "", total: 5 },
    ],
  )
}

test bundle_rejects_duplicate() {
  !bundle_well_formed(
    [
      VestedAsset { policy: token_policy, name: "TOKEN", total: 100 },
      VestedAsset { policy: token_policy, name: "TOKEN", total: 100 },
    ],
  )
}

test bundle_rejects_unsorted_names() {
  !bundle_well_formed(
    [
      VestedAsset { policy: token_policy, name: "B", total: 1 },
      VestedAsset { policy: token_policy, name: "A", total: 1 },
    ],
  )
}

test bundle_rejects_unsorted_policies() {
  !bundle_well_formed(
    [
      VestedAsset { policy: other_policy, name: "", total: 1 },
      VestedAsset { policy: token_policy, name: "", total: 1 },
    ],
  )
}

test bundle_rejects_negative_total_single() {
  !bundle_well_formed([VestedAsset { policy: "", name: "", total: -1 }])
}

test bundle_rejects_negative_total_last() {
  !bundle_well_formed(
    [
      VestedAsset { policy: "", name: "", total: 1 },
      VestedAsset { policy: token_policy, name: "", total: -1 },
    ],
  )
}

fn duplicate_datum() -> VestingDatum {
  VestingDatum {
    ..datum(),
    vesting: [
      VestedAsset { policy: token_policy, name: "TOKEN", total: 100 },
      VestedAsset { policy: token_policy, name: "TOKEN", total: 100 },
    ],
  }
}

test rejects_claim_with_duplicate_assets() fail {
  // 200 TOKEN locked against two 100-entries. Without the check, each entry
  // would be met by the same 100 in the continuation, so 100 could be taken
  // at `start` when nothing has vested.
  let d = duplicate_datum()
  let locked = assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 200))
  let kept = assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 100))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1000, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test rejects_claim_with_negative_total() fail {
  // A negative total would leave the asset unprotected.
  let d = VestingDatum {
    ..datum(),
    vesting: [VestedAsset { policy: token_policy, name: "TOKEN", total: -50 }],
  }
  let locked = assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 100))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(
    1000,
    [input],
    [output_with(d, assets.from_lovelace(2_000_000))],
    [beneficiary_key],
  )
  validate_claim(d, input.output, tx)
}

test rejects_full_claim_with_duplicate_assets() fail {
  // Fails closed even after `end_time`; the locker recovers instead.
  let d = duplicate_datum()
  let input = input_with(d, assets.from_asset(token_policy, "TOKEN", 200), 0)
  let tx = claim_tx(2000, [input], [], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test cancel_recovers_malformed_bundle() {
  // A malformed bundle must not strand funds: `Cancel` ignores it.
  let d = duplicate_datum()
  let input = input_with(d, assets.from_asset(token_policy, "TOKEN", 200), 0)
  let tx = claim_tx(3001, [input], [], [locker_key])
  validate_cancel(d, tx)
}

// ------------------------------------------- full address match (stake credential)
//
// Continuations must sit at the spent input's full address, so the beneficiary
// cannot move the locked ada's delegation. `k` is counted per full address.

const stake_a = #"66666666666666666666666666666666666666666666666666666666"

const stake_b = #"77777777777777777777777777777777777777777777777777777777"

fn staked(stake: ByteArray) -> Address {
  from_script(own_script) |> with_delegation_key(stake)
}

fn input_at(
  address: Address,
  d: VestingDatum,
  value: Value,
  index: Int,
) -> Input {
  let input = input_with(d, value, index)
  Input { ..input, output: Output { ..input.output, address } }
}

fn output_at(address: Address, d: VestingDatum, value: Value) -> Output {
  Output { ..output_with(d, value), address }
}

test staked_partial_claim_ok() {
  let input = input_at(staked(stake_a), datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(
    1500,
    [input],
    [output_at(staked(stake_a), datum(), assets.from_lovelace(50))],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

test rejects_stake_credential_change() fail {
  let input = input_at(staked(stake_a), datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(
    1500,
    [input],
    [output_at(staked(stake_b), datum(), assets.from_lovelace(50))],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

test rejects_stake_credential_removal() fail {
  let input = input_at(staked(stake_a), datum(), assets.from_lovelace(100), 0)
  let tx = claim_tx(
    1500,
    [input],
    [output_with(datum(), assets.from_lovelace(50))],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

test same_datum_different_stake_each_keeps_own_continuation_ok() {
  // Same datum at two stake addresses: two separate instances (k = 1 each),
  // each continuing at its own address.
  let in_a = input_at(staked(stake_a), datum(), assets.from_lovelace(100), 0)
  let in_b = input_at(staked(stake_b), datum(), assets.from_lovelace(100), 1)
  let tx = claim_tx(
    1500,
    [in_a, in_b],
    [
      output_at(staked(stake_a), datum(), assets.from_lovelace(50)),
      output_at(staked(stake_b), datum(), assets.from_lovelace(50)),
    ],
    [beneficiary_key],
  )
  validate_claim(datum(), in_a.output, tx) && validate_claim(
    datum(),
    in_b.output,
    tx,
  )
}

test rejects_moving_instance_to_other_stake_address() fail {
  // Both continuations at stake_a: instance B has no continuation at its own
  // address, so its spend is rejected.
  let in_a = input_at(staked(stake_a), datum(), assets.from_lovelace(100), 0)
  let in_b = input_at(staked(stake_b), datum(), assets.from_lovelace(100), 1)
  let tx = claim_tx(
    1500,
    [in_a, in_b],
    [
      output_at(staked(stake_a), datum(), assets.from_lovelace(50)),
      output_at(staked(stake_a), datum(), assets.from_lovelace(50)),
    ],
    [beneficiary_key],
  )
  validate_claim(datum(), in_b.output, tx)
}

// ------------------------------------------------------- clean continuations
//
// A continuation holds only ada and listed assets, and no reference script.

const spam_policy = #"88888888888888888888888888888888888888888888888888888888"

test rejects_unlisted_token_in_continuation() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let kept = assets.from_lovelace(50)
    |> assets.merge(assets.from_asset(spam_policy, "SPAM", 1))
  let tx = claim_tx(
    1500,
    [input],
    [output_with(datum(), kept)],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

test rejects_unlisted_name_under_listed_policy() fail {
  // Same policy as a listed asset, different name: still unlisted.
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
    |> assets.merge(assets.from_asset(token_policy, "OTHER", 1))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1500, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test rejects_reference_script_on_continuation() fail {
  let input = input_with(datum(), assets.from_lovelace(100), 0)
  let continuation = Output {
    ..output_with(datum(), assets.from_lovelace(50)),
    reference_script: Some(auth_script),
  }
  let tx = claim_tx(1500, [input], [continuation], [beneficiary_key])
  validate_claim(datum(), input.output, tx)
}

test ada_only_continuation_for_token_bundle_ok() {
  // Ada is always allowed (min-ada), even when the bundle lists no ada.
  let d = VestingDatum {
    ..datum(),
    vesting: [VestedAsset { policy: token_policy, name: "TOKEN", total: 10 }],
  }
  let locked = assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 10))
  let kept = assets.from_lovelace(2_000_000)
    |> assets.merge(assets.from_asset(token_policy, "TOKEN", 5))
  let input = input_with(d, locked, 0)
  let tx = claim_tx(1500, [input], [output_with(d, kept)], [beneficiary_key])
  validate_claim(d, input.output, tx)
}

test unlisted_token_in_input_can_be_swept_ok() {
  // An unlisted token the locker added at lock time is surplus: the first
  // partial claim takes it out.
  let locked = assets.from_lovelace(100)
    |> assets.merge(assets.from_asset(spam_policy, "EXTRA", 1))
  let input = input_with(datum(), locked, 0)
  let tx = claim_tx(
    1500,
    [input],
    [output_with(datum(), assets.from_lovelace(50))],
    [beneficiary_key],
  )
  validate_claim(datum(), input.output, tx)
}

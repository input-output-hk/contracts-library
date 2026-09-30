// Minimum flow tests for the transformation script (spec §4.4, T3).
// Fixture style mirrors `lib/dao/proposal/proposal.test.ak`.

use aiken/interval
use cardano/address.{
  Address, Credential, Script, from_script, with_delegation_script,
}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/transformation
use event_triggered/types.{
  BondExtra, ReferenceDatum, ScheduleStep, TransformationParams,
}

// ------------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const plb_script = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const native_policy =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const tscript_hash = #"33333333333333333333333333333333333333333333333333333333"

const ref_name = "REF222"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn schedule() -> List<ScheduleStep> {
  [
    ScheduleStep { deadline: 1000, value: 1040 },
    ScheduleStep { deadline: 2000, value: 1081 },
    ScheduleStep { deadline: 3000, value: 1124 },
    ScheduleStep { deadline: 4000, value: 1169 },
  ]
}

fn params() -> TransformationParams {
  TransformationParams { reference_name: ref_name, schedule: schedule() }
}

fn account() -> Credential {
  Script(tscript_hash)
}

fn plb_script_addr() -> Address {
  from_script(plb_script) |> with_delegation_script(tscript_hash)
}

fn ref_datum(value: Int) -> ReferenceDatum {
  ReferenceDatum {
    metadata: #"",
    version: 1,
    extra: BondExtra { schedule: schedule(), value, native_policy },
  }
}

fn ref_output(value: Int) -> Output {
  Output {
    address: plb_script_addr(),
    value: assets.from_asset(cip_policy, ref_name, 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(ref_datum(value)),
    reference_script: None,
  }
}

fn ref_input(index: Int, value: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: ref_output(value),
  }
}

fn transform_tx(now: Int, in_value: Int, out_value: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [ref_input(0, in_value)],
    outputs: [ref_output(out_value)],
    validity_range: interval.after(now),
  }
}

fn check(self: Transaction) -> Bool {
  transformation.validate(account(), self, params())
}

// ------------------------------------------------------------------- tests

test transform_ok() {
  // now ∈ [d1, d2): the recorded value steps to v1
  check(transform_tx(1500, 1000, 1040))
}

test late_submission_jumps_to_current_step_ok() {
  // stale input (v1), but now ∈ [d3, d4) lands on v3
  check(transform_tx(3500, 1040, 1124))
}

test final_write_at_d4_ok() {
  // the final v4 write is admitted at exactly d4
  check(transform_tx(4000, 1124, 1169))
}

test rejects_before_d1() {
  !check(transform_tx(999, 1000, 1000))
}

test rejects_after_exhaustion() {
  !check(transform_tx(4001, 1169, 1169))
}

test rejects_schedule_tampering() {
  // the output datum must mirror the baked schedule (I4)
  let tampered = ReferenceDatum {
    ..ref_datum(1040),
    extra: BondExtra {
      schedule: [ScheduleStep { deadline: 1000, value: 9999 }],
      value: 1040,
      native_policy,
    },
  }
  let bad = Output { ..ref_output(1040), datum: InlineDatum(tampered) }
  !check(Transaction { ..transform_tx(1500, 1000, 1040), outputs: [bad] })
}

test rejects_metadata_tampering() {
  let tampered = ReferenceDatum { ..ref_datum(1040), metadata: #"ff" }
  let bad = Output { ..ref_output(1040), datum: InlineDatum(tampered) }
  !check(Transaction { ..transform_tx(1500, 1000, 1040), outputs: [bad] })
}

test rejects_version_tampering() {
  let tampered = ReferenceDatum { ..ref_datum(1040), version: 2 }
  let bad = Output { ..ref_output(1040), datum: InlineDatum(tampered) }
  !check(Transaction { ..transform_tx(1500, 1000, 1040), outputs: [bad] })
}

test rejects_native_policy_tampering() {
  // the published graduated-asset policy is frozen (§3.3)
  let tampered = ReferenceDatum {
    ..ref_datum(1040),
    extra: BondExtra {
      schedule: schedule(),
      value: 1040,
      native_policy: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    },
  }
  let bad = Output { ..ref_output(1040), datum: InlineDatum(tampered) }
  !check(Transaction { ..transform_tx(1500, 1000, 1040), outputs: [bad] })
}

test rejects_stale_value_in_later_window() {
  // now ∈ [d2, d3) must record v2 (1081), not the stale v1
  !check(transform_tx(2500, 1040, 1040))
}

test rejects_moved_token() {
  // the continuation must stay at the reference token's own address
  let moved = Output { ..ref_output(1040), address: from_script(plb_script) }
  !check(Transaction { ..transform_tx(1500, 1000, 1040), outputs: [moved] })
}

test rejects_vacuous_withdrawal() fail {
  // no input staked to the transformation script → abort
  !check(
    Transaction {
      ..placeholder,
      inputs: [],
      outputs: [ref_output(1040)],
      validity_range: interval.after(1500),
    },
  )
}

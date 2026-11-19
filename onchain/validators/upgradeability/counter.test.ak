use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction, placeholder,
}
use upgradeability/counter.{
  CounterDatum, Tick, Upgrade, spent_with_upgrade, validate_counter_migrate,
  validate_counter_tick,
}

// ------------------------------------------------------------------- fixtures

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const forwarder_hash =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const v2_hash = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const unrelated_hash =
  #"99999999999999999999999999999999999999999999999999999999"

const token_policy = #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const token_name = "tok"

const vkh = #"11111111111111111111111111111111111111111111111111111111"

/// The input value plus one unit of a stand-in state token.
fn with_token(value: assets.Value) -> assets.Value {
  assets.add(value, token_policy, token_name, 1)
}

fn owner() -> Credential {
  VerificationKey(vkh)
}

fn counter_datum(count: Int) -> CounterDatum {
  CounterDatum { count, owner: owner(), prev_input: None }
}

/// A continuation output at `hash` continuing the UTxO referenced by `prev`.
fn continuation_output(
  hash: ScriptHash,
  prev: OutputReference,
  count: Int,
) -> Output {
  continuation_output_with(
    hash,
    prev,
    count,
    assets.from_lovelace(2_000_000),
    None,
  )
}

/// A continuation output with a custom value and reference script.
fn continuation_output_with(
  hash: ScriptHash,
  prev: OutputReference,
  count: Int,
  value: assets.Value,
  reference_script: Option<ScriptHash>,
) -> Output {
  Output {
    address: from_script(hash),
    value,
    datum: InlineDatum(
      CounterDatum { count, owner: owner(), prev_input: Some(prev) },
    ),
    reference_script,
  }
}

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

/// An input at `hash`'s address carrying a counter datum.
fn counter_input(hash: ScriptHash, index: Int, count: Int) -> Input {
  counter_input_with(hash, index, count, assets.from_lovelace(2_000_000))
}

/// An input at `hash`'s address carrying a counter datum and a custom value.
fn counter_input_with(
  hash: ScriptHash,
  index: Int,
  count: Int,
  value: assets.Value,
) -> Input {
  Input {
    output_reference: ref(index),
    output: Output {
      address: from_script(hash),
      value,
      datum: InlineDatum(counter_datum(count)),
      reference_script: None,
    },
  }
}

/// An output at `hash`'s address carrying a counter datum.
fn counter_output(hash: ScriptHash, count: Int) -> Output {
  Output {
    address: from_script(hash),
    value: assets.from_lovelace(2_000_000),
    datum: InlineDatum(counter_datum(count)),
    reference_script: None,
  }
}

// ------------------------------------------------------------- counter steps

test tick_admits_increment() {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(forwarder_hash, ref(0), 6)],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_wrong_count() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(forwarder_hash, ref(0), 5)],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_missing_continuation() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [counter_output(unrelated_hash, 6)],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_mistagged_continuation() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(forwarder_hash, ref(1), 6)],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_admits_continuation_with_extra_lovelace() {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [
      continuation_output_with(
        forwarder_hash,
        ref(0),
        6,
        assets.from_lovelace(3_000_000),
        None,
      ),
    ],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_admits_preserving_input_token() {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input_with(
        forwarder_hash,
        0,
        5,
        with_token(assets.from_lovelace(2_000_000)),
      ),
    ],
    outputs: [
      continuation_output_with(
        forwarder_hash,
        ref(0),
        6,
        with_token(assets.from_lovelace(2_000_000)),
        None,
      ),
    ],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_admits_token_preserved_and_extra_lovelace() {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input_with(
        forwarder_hash,
        0,
        5,
        with_token(assets.from_lovelace(2_000_000)),
      ),
    ],
    outputs: [
      continuation_output_with(
        forwarder_hash,
        ref(0),
        6,
        with_token(assets.from_lovelace(3_000_000)),
        None,
      ),
    ],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_continuation_with_reference_script() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [
      continuation_output_with(
        forwarder_hash,
        ref(0),
        6,
        assets.from_lovelace(2_000_000),
        Some(unrelated_hash),
      ),
    ],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_continuation_with_extra_token() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [
      continuation_output_with(
        forwarder_hash,
        ref(0),
        6,
        with_token(assets.from_lovelace(2_000_000)),
        None,
      ),
    ],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_rejects_continuation_dropping_input_token() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input_with(
        forwarder_hash,
        0,
        5,
        with_token(assets.from_lovelace(2_000_000)),
      ),
    ],
    outputs: [continuation_output(forwarder_hash, ref(0), 6)],
  }
  validate_counter_tick(tx, ref(0))
}

test tick_binds_each_input_to_its_own_continuation() {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input(forwarder_hash, 0, 5),
      counter_input(forwarder_hash, 1, 5),
    ],
    outputs: [
      continuation_output(forwarder_hash, ref(0), 6),
      continuation_output(forwarder_hash, ref(1), 6),
    ],
  }
  and {
    validate_counter_tick(tx, ref(0)),
    validate_counter_tick(tx, ref(1)),
  }
}

test tick_rejects_collapsed_shared_continuation() fail {
  // M1: two same-count UTxOs settled by one continuation tagged for only one
  // of them. The second input has no continuation of its own, so the collapse
  // cannot drain its value.
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input(forwarder_hash, 0, 5),
      counter_input(forwarder_hash, 1, 5),
    ],
    outputs: [continuation_output(forwarder_hash, ref(0), 6)],
  }
  and {
    validate_counter_tick(tx, ref(0)),
    validate_counter_tick(tx, ref(1)),
  }
}

test migrate_admits_state_preserved_at_v2() {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(v2_hash, ref(0), 5)],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_rejects_output_still_at_v1() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(forwarder_hash, ref(0), 5)],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_rejects_mistagged_continuation() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [continuation_output(v2_hash, ref(1), 5)],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_rejects_continuation_with_reference_script() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [
      continuation_output_with(
        v2_hash,
        ref(0),
        5,
        assets.from_lovelace(2_000_000),
        Some(unrelated_hash),
      ),
    ],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_rejects_continuation_with_extra_token() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 5)],
    outputs: [
      continuation_output_with(
        v2_hash,
        ref(0),
        5,
        with_token(assets.from_lovelace(2_000_000)),
        None,
      ),
    ],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_rejects_continuation_dropping_input_token() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input_with(
        forwarder_hash,
        0,
        5,
        with_token(assets.from_lovelace(2_000_000)),
      ),
    ],
    outputs: [continuation_output(v2_hash, ref(0), 5)],
  }
  validate_counter_migrate(tx, ref(0), from_script(v2_hash))
}

test migrate_binds_each_input_to_its_own_continuation() {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input(forwarder_hash, 0, 5),
      counter_input(forwarder_hash, 1, 5),
    ],
    outputs: [
      continuation_output(v2_hash, ref(0), 5),
      continuation_output(v2_hash, ref(1), 5),
    ],
  }
  and {
    validate_counter_migrate(tx, ref(0), from_script(v2_hash)),
    validate_counter_migrate(tx, ref(1), from_script(v2_hash)),
  }
}

test migrate_rejects_collapsed_shared_continuation() fail {
  let tx = Transaction {
    ..placeholder,
    inputs: [
      counter_input(forwarder_hash, 0, 5),
      counter_input(forwarder_hash, 1, 5),
    ],
    outputs: [continuation_output(v2_hash, ref(0), 5)],
  }
  and {
    validate_counter_migrate(tx, ref(0), from_script(v2_hash)),
    validate_counter_migrate(tx, ref(1), from_script(v2_hash)),
  }
}

// --------------------------------------------------------- redeemer binding

test spent_with_upgrade_detects_action() {
  let upgrade: Data = Upgrade
  let tx = Transaction {
    ..placeholder,
    redeemers: [Pair(Spend(ref(0)), upgrade)],
  }
  spent_with_upgrade(tx, ref(0))
}

test spent_with_upgrade_rejects_other_action() fail {
  let tick: Data = Tick
  let tx = Transaction { ..placeholder, redeemers: [Pair(Spend(ref(0)), tick)] }
  spent_with_upgrade(tx, ref(0))
}

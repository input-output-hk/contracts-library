use aiken/collection/dict.{Dict}
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script, VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction, placeholder,
}
use settings/types.{SettingsDatum}
use upgradeability/counter.{
  CounterDatum, Tick, Upgrade, spent_with_upgrade, validate_counter_migrate,
  validate_counter_tick,
}
use upgradeability/forward.{validate_forward}
use upgradeability/migrate.{validate_upgrade}
use upgradeability/registry.{decode_registry, forwarded_inputs, lookup}

// ------------------------------------------------------------------- fixtures

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const settings_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const settings_name = "settings"

const forwarder_hash =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const logic_hash = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const migration_hash =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const v2_hash = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const unrelated_hash =
  #"99999999999999999999999999999999999999999999999999999999"

const vkh = #"11111111111111111111111111111111111111111111111111111111"

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
  Output {
    address: from_script(hash),
    value: assets.from_lovelace(2_000_000),
    datum: InlineDatum(
      CounterDatum { count, owner: owner(), prev_input: Some(prev) },
    ),
    reference_script: None,
  }
}

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

/// An input at `hash`'s address carrying a counter datum.
fn counter_input(hash: ScriptHash, index: Int, count: Int) -> Input {
  Input {
    output_reference: ref(index),
    output: Output {
      address: from_script(hash),
      value: assets.from_lovelace(2_000_000),
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

/// The settings reference input that carries `registry` as its `current` value.
fn settings_ref(registry: Dict<ByteArray, ScriptHash>) -> Input {
  Input {
    output_reference: ref(99),
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_lovelace(2_000_000)
        |> assets.add(settings_policy, settings_name, 1),
      datum: InlineDatum(
        SettingsDatum { current: registry, next: None, next_apply: None },
      ),
      reference_script: None,
    },
  }
}

fn registry(
  entries: Pairs<ByteArray, ScriptHash>,
) -> Dict<ByteArray, ScriptHash> {
  dict.from_pairs(entries)
}

// ------------------------------------------------------------------ registry

test decode_and_lookup() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  when lookup(decode_registry(r), forwarder_hash) is {
    Some(h) -> h == logic_hash
    None -> False
  }
}

test lookup_absent_is_none() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  lookup(decode_registry(r), unrelated_hash) == None
}

test forwarded_inputs_filters_by_registered_hash() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let inputs = [
    counter_input(forwarder_hash, 0, 0),
    counter_input(unrelated_hash, 1, 0),
  ]
  list.length(forwarded_inputs(inputs, r, logic_hash)) == 1
}

// ------------------------------------------------------------ forced forward

test forward_admits_when_logic_runs() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(logic_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, ref(0), tx)
}

test forward_rejects_without_logic_withdrawal() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [],
  }
  validate_forward(settings_policy, settings_name, ref(0), tx)
}

test forward_rejects_wrong_delegate() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(unrelated_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, ref(0), tx)
}

test forward_rejects_unregistered_own_hash() fail {
  // the forwarder's own hash is not a key in the registry
  let r = registry([Pair(unrelated_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(logic_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, ref(0), tx)
}

// ------------------------------------------------------------- opt-in upgrade

test upgrade_admits_with_consent_and_delegate() {
  let r = registry([Pair(forwarder_hash, migration_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(migration_hash), 0)],
    extra_signatories: [vkh],
  }
  validate_upgrade(owner(), settings_policy, settings_name, ref(0), tx)
}

test upgrade_rejects_without_consent() fail {
  let r = registry([Pair(forwarder_hash, migration_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(migration_hash), 0)],
    extra_signatories: [],
  }
  validate_upgrade(owner(), settings_policy, settings_name, ref(0), tx)
}

test upgrade_rejects_without_migration_script() fail {
  let r = registry([Pair(forwarder_hash, migration_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [counter_input(forwarder_hash, 0, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [],
    extra_signatories: [vkh],
  }
  validate_upgrade(owner(), settings_policy, settings_name, ref(0), tx)
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

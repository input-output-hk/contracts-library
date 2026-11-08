use aiken/collection/dict.{Dict}
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script, VerificationKey, from_script}
use cardano/assets
use cardano/script_context.{ScriptInfo, Spending}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction, placeholder,
}
use settings/types.{SettingsDatum}
use upgradeability/delegate.{forwarded_by, forwarded_inputs, spend_redeemer}
use upgradeability/forward.{validate_forward}
use upgradeability/migrate.{validate_upgrade}
use upgradeability/registry.{decode_registry, lookup}

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

const unrelated_hash =
  #"99999999999999999999999999999999999999999999999999999999"

const vkh = #"11111111111111111111111111111111111111111111111111111111"

fn owner() -> Credential {
  VerificationKey(vkh)
}

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

/// The purpose of spending the input at `output`.
fn spending(output: OutputReference) -> ScriptInfo {
  Spending { output, datum: None }
}

/// An input at `hash`'s address; the predicates never read its datum.
fn script_input(hash: ScriptHash, index: Int) -> Input {
  let datum: Data = 0
  Input {
    output_reference: ref(index),
    output: Output {
      address: from_script(hash),
      value: assets.from_lovelace(2_000_000),
      datum: InlineDatum(datum),
      reference_script: None,
    },
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

/// Raw registry `Data`, in the given entry order (no sorting).
fn raw_registry(entries: Pairs<ByteArray, ByteArray>) -> Data {
  let raw: Data = entries
  raw
}

test decode_registry_accepts_sorted_entries() {
  // 0x99.. < 0xbb..: keys in strictly ascending byte order.
  let r = decode_registry(
    raw_registry(
      [Pair(unrelated_hash, migration_hash), Pair(forwarder_hash, logic_hash)],
    ),
  )
  and {
    lookup(r, forwarder_hash) == Some(logic_hash),
    lookup(r, unrelated_hash) == Some(migration_hash),
  }
}

test decode_registry_rejects_unsorted_keys() fail {
  let r = decode_registry(
    raw_registry(
      [Pair(forwarder_hash, logic_hash), Pair(unrelated_hash, migration_hash)],
    ),
  )
  lookup(r, forwarder_hash) == Some(logic_hash)
}

test decode_registry_rejects_duplicate_keys() fail {
  let r = decode_registry(
    raw_registry(
      [Pair(forwarder_hash, logic_hash), Pair(forwarder_hash, migration_hash)],
    ),
  )
  lookup(r, forwarder_hash) != None
}

test decode_registry_rejects_short_delegate_hash() fail {
  let r = decode_registry(raw_registry([Pair(forwarder_hash, #"cccc")]))
  lookup(r, forwarder_hash) != None
}

test decode_registry_rejects_non_map() fail {
  let not_a_map: Data = 5
  lookup(decode_registry(not_a_map), forwarder_hash) == None
}

test forwarded_inputs_filters_by_registered_hash() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let inputs = [
    script_input(forwarder_hash, 0),
    script_input(unrelated_hash, 1),
  ]
  list.length(forwarded_inputs(inputs, r, logic_hash)) == 1
}

test forwarded_by_returns_delegated_inputs() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0), script_input(unrelated_hash, 1)],
    reference_inputs: [settings_ref(r)],
  }
  list.length(
    forwarded_by(tx, settings_policy, settings_name, Script(logic_hash)),
  ) == 1
}

/// A delegate built for another settings instance finds no targets there; it
/// must reject instead of passing vacuously over an empty set.
test forwarded_by_rejects_when_nothing_is_delegated() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(unrelated_hash, 0)],
    reference_inputs: [settings_ref(r)],
  }
  forwarded_by(tx, settings_policy, settings_name, Script(logic_hash)) != []
}

test forwarded_by_rejects_key_account() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
  }
  forwarded_by(tx, settings_policy, settings_name, VerificationKey(vkh)) != []
}

// ------------------------------------------------------------ forced forward

test forward_admits_when_logic_runs() {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(logic_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, spending(ref(0)), tx)
}

test forward_rejects_without_logic_withdrawal() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [],
  }
  validate_forward(settings_policy, settings_name, spending(ref(0)), tx)
}

test forward_rejects_wrong_delegate() fail {
  let r = registry([Pair(forwarder_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(unrelated_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, spending(ref(0)), tx)
}

test forward_rejects_unregistered_own_hash() fail {
  // the forwarder's own hash is not a key in the registry
  let r = registry([Pair(unrelated_hash, logic_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [Pair(Script(logic_hash), 0)],
  }
  validate_forward(settings_policy, settings_name, spending(ref(0)), tx)
}

// ------------------------------------------------------------- opt-in upgrade

test upgrade_admits_with_consent_and_delegate() {
  let r = registry([Pair(forwarder_hash, migration_hash)])
  let tx = Transaction {
    ..placeholder,
    inputs: [script_input(forwarder_hash, 0)],
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
    inputs: [script_input(forwarder_hash, 0)],
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
    inputs: [script_input(forwarder_hash, 0)],
    reference_inputs: [settings_ref(r)],
    withdrawals: [],
    extra_signatories: [vkh],
  }
  validate_upgrade(owner(), settings_policy, settings_name, ref(0), tx)
}

// ---------------------------------------------------------- spend redeemer

test spend_redeemer_returns_the_input_action() {
  let tick: Data = 0
  let upgrade: Data = 1
  let tx = Transaction {
    ..placeholder,
    redeemers: [Pair(Spend(ref(0)), tick), Pair(Spend(ref(1)), upgrade)],
  }
  and {
    spend_redeemer(tx, ref(0)) == Some(tick),
    spend_redeemer(tx, ref(1)) == Some(upgrade),
  }
}

test spend_redeemer_is_none_for_unspent_ref() {
  let tick: Data = 0
  let tx = Transaction { ..placeholder, redeemers: [Pair(Spend(ref(0)), tick)] }
  spend_redeemer(tx, ref(1)) == None
}

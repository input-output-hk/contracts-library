use aiken/builtin
use aiken/collection/dict.{Dict}
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Input, OutputReference, Transaction, find_input}
use settings/utils.{get_settings_datum}

/// The upgrade registry: a map from a protocol validator's own script hash to
/// the script hash of its currently-active delegate.
///
/// It is stored as the `current` value of a settings UTxO (see
/// `docs/upgradeability/spec.md`), so changing it inherits the settings
/// protocol's propose/apply split, timelock (`apply_delay`), and pluggable
/// authorization (`propose_auth` / `apply_auth`).
///
/// The same map serves both mechanisms: the *key* is always the immutable hash
/// of the validator a user is interacting with, and the *value* is the script
/// that must run. What differs is only which paths forward:
///
/// - **forced** (beacon indirection): the validator forwards every path, so
///   the value is the protocol's logic; and
/// - **opt-in** (migration): the validator forwards only its `Upgrade` path,
///   so the value is the migration script.
pub type Registry =
  Dict<ByteArray, ScriptHash>

/// Decode a registry from its on-chain `Data` representation (a Plutus `Map`
/// from byte arrays to byte arrays). Fails on any other shape.
pub fn decode_registry(data: Data) -> Registry {
  let entries = list.map(
    builtin.un_map_data(data),
    fn(entry) {
      Pair(builtin.un_b_data(entry.1st), builtin.un_b_data(entry.2nd))
    },
  )
  dict.from_pairs(entries)
}

/// Read the upgrade registry from the settings UTxO identified by
/// `settings_policy` + `settings_token_name`, decoding its opaque `current`
/// value.
///
/// Fails (rejects the transaction) if no such settings UTxO is present as a
/// reference input or if its `current` value is not registry-shaped.
pub fn get_registry(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
) -> Registry {
  let settings_datum = get_settings_datum(
    self,
    settings_policy,
    settings_token_name,
  )
  decode_registry(settings_datum.current)
}

/// The delegate script hash registered for `own_hash`, if any.
pub fn lookup(registry: Registry, own_hash: ScriptHash) -> Option<ScriptHash> {
  dict.get(registry, own_hash)
}

/// The script hash that owns the input referenced by `own_ref` — the immutable
/// "own hash" a validator keys its registry entry by.
pub fn own_script_hash(
  inputs: List<Input>,
  own_ref: OutputReference,
) -> ScriptHash {
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(hash) = own_input.output.address.payment_credential
  hash
}

/// Every transaction input whose address is a script registered to delegate to
/// `logic_hash`.
///
/// These are the UTxOs a logic / migration script is responsible for
/// validating. A well-formed logic script must validate *all* of them, not
/// just one, so an attacker cannot have it check a benign input while another
/// forwarded input is drained.
pub fn forwarded_inputs(
  inputs: List<Input>,
  registry: Registry,
  logic_hash: ScriptHash,
) -> List<Input> {
  list.filter(
    inputs,
    fn(input) {
      when input.output.address.payment_credential is {
        Script(h) -> lookup(registry, h) == Some(logic_hash)
        _ -> False
      }
    },
  )
}

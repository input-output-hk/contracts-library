use aiken/collection/dict.{Dict}
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use aiken/primitive/bytearray
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

/// Decode a registry from its on-chain `Data` representation: a Plutus `Map`
/// from byte arrays to 28-byte script hashes, with keys in strictly ascending
/// byte order. Fails on any other shape, on unsorted or duplicate keys, and on
/// a value that is not 28 bytes long.
///
/// Requiring sorted keys makes decoding a single linear pass (no re-sorting on
/// every spend), rules out ambiguous duplicate entries, and lets lookups stop
/// early. Writers (governance, off-chain builders) must sort the map by key.
pub fn decode_registry(data: Data) -> Registry {
  expect entries: Pairs<ScriptHash, ScriptHash> = data
  dict.from_ascending_pairs_with(
    entries,
    fn(delegate) { bytearray.length(delegate) == 28 },
  )
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

/// Whether the delegate registered for `own_hash` runs in this transaction as a
/// reward withdrawal (the withdraw-0 convention).
///
/// Fails (rejects the transaction) if the registry can't be read or has no
/// entry for `own_hash`; an unregistered validator has no delegate to admit it.
pub fn delegate_invoked(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  own_hash: ScriptHash,
) -> Bool {
  let registry = get_registry(self, settings_policy, settings_token_name)
  expect Some(delegate) = lookup(registry, own_hash)
  pairs.has_key(self.withdrawals, Script(delegate))
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

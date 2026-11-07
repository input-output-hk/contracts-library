//// Helpers for delegate scripts: the logic (forced) and migration (opt-in)
//// scripts a registry points at. They run once per transaction under the
//// withdraw-0 convention and must validate every input forwarded to them.

use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Input, OutputReference, Spend, Transaction}
use upgradeability/registry.{Registry, get_registry, lookup}

/// The inputs a delegate (logic or migration script) must validate: every input
/// registered to delegate to the script running as `account`.
///
/// Fails (rejects the transaction) if `account` is not a script, the registry
/// can't be read, or no input is delegated to this script. A delegate that
/// validates nothing has no legitimate use, and accepting an empty set would
/// let a delegate built for another settings instance pass vacuously: an
/// attacker could reference that instance's settings UTxO, find no targets, and
/// spend every forwarder unchecked.
pub fn forwarded_by(
  self: Transaction,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  account: Credential,
) -> List<Input> {
  expect Script(own_hash) = account
  let registry = get_registry(self, settings_policy, settings_token_name)
  let targets = forwarded_inputs(self.inputs, registry, own_hash)
  expect targets != []
  targets
}

/// The redeemer the input at `ref` was spent with, if it is a script input of
/// this transaction.
///
/// A forwarder ignores its own redeemer, so this is how a logic script learns
/// each forwarded input's action: one logic run validates every forwarded
/// input, and each of them may carry a different action.
pub fn spend_redeemer(self: Transaction, ref: OutputReference) -> Option<Data> {
  pairs.get_first(self.redeemers, Spend(ref))
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

use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/script_context.{
  Minting, Publishing, ScriptInfo, Spending, Voting, Withdrawing,
}
use cardano/transaction.{Transaction}
use upgradeability/credentials.{certificate_credential, voter_credential}
use upgradeability/registry.{delegate_invoked, own_script_hash}

/// Forced forwarding (beacon indirection): admit any use of the forwarder, for
/// any purpose, iff the script registered for its own hash runs as a reward
/// withdrawal (withdraw-0). That script validates everything delegated to it.
///
/// **Load-bearing constraint.** A validator only becomes forced-upgradeable if
/// *every* purpose and redeemer path calls this predicate from day one. A plain
/// validator that adds a dedicated `Upgrade` path later is opt-in, not forced.
pub fn validate_forward(
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  info: ScriptInfo,
  self: Transaction,
) -> Bool {
  delegate_invoked(
    self,
    settings_policy,
    settings_token_name,
    own_hash(self, info),
  )
}

/// The running script's own hash, from whichever purpose runs it.
pub fn own_hash(self: Transaction, info: ScriptInfo) -> ScriptHash {
  let credential = when info is {
    Spending { output, .. } -> Script(own_script_hash(self.inputs, output))
    Minting(policy_id) -> Script(policy_id)
    Withdrawing(credential) -> credential
    Publishing { certificate, .. } -> certificate_credential(certificate)
    Voting(voter) -> voter_credential(voter)
    _ -> fail
  }
  expect Script(hash) = credential
  hash
}

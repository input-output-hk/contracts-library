use aiken/collection/pairs
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use upgradeability/registry.{get_registry, lookup, own_script_hash}

/// Opt-in migration (Approach A).
///
/// The protocol's own validator keeps its native logic for every normal path
/// and exposes a dedicated `Upgrade` path that calls this predicate. Two
/// independent conditions must hold:
///
/// 1. **Consent.** `user_auth` — the credential of the user whose UTxO is being
///    relocated — authorizes the transaction. This is enforced *here*, in the
///    immutable validator, not in the registered script.
/// 2. **Delegation.** The migration script registered for the protocol's own
///    hash is invoked as a reward withdrawal, and is responsible for validating
///    the V1 → V2 transformation.
///
/// Because consent is native, a governance repoint of the registered migration
/// script can change *how* a migration is performed but can never move a
/// user's funds without that user's authorization. That is what makes this
/// opt-in rather than forced.
///
/// Like `forward.validate_forward`, this asserts only about the own input, the
/// settings UTxO, and the withdrawal key set (`ARCHITECTURE.md` §1.1).
pub fn validate_upgrade(
  user_auth: Credential,
  settings_policy: PolicyId,
  settings_token_name: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, withdrawals, extra_signatories, .. } = self
  let registry = get_registry(self, settings_policy, settings_token_name)
  let own = own_script_hash(inputs, own_ref)
  let delegated = when lookup(registry, own) is {
    Some(migration_hash) -> pairs.has_key(withdrawals, Script(migration_hash))
    None -> False
  }
  and {
    is_authorized(user_auth, extra_signatories, withdrawals),
    delegated,
  }
}

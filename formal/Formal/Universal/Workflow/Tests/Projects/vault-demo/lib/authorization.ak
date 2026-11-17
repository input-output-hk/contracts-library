//// Pluggable authorization (experimental — see `docs/ARCHITECTURE.md` §3).
////
//// A contract states *that* an action needs authorization by holding a
//// `Credential`, without hardcoding *how* that authorization is decided. The
//// same contract then composes with a single key, a multisig, a DAO, or a
//// smart wallet, because each of those is ultimately reducible to a credential
//// that can be satisfied within a transaction:
////
//// - a `VerificationKey` credential is satisfied by a signature on the tx;
//// - a `Script` credential is satisfied by *invoking that script* in the tx.
////   We use the withdraw-0 convention: the authorizing script runs as a reward
////   withdrawal (commonly of zero ada), which forces it to validate and
////   approve. This is the cheapest, most composable way to demand "this script
////   must run and agree" without the consuming contract knowing anything about
////   what the script checks.

use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{Lovelace}

/// Is the given authorizer credential satisfied by this transaction?
///
/// - `VerificationKey(hash)` → `hash` must appear in `extra_signatories`.
/// - `Script(hash)` → a withdrawal keyed by that script credential must be
///   present (withdraw-0 pattern), which means the script ran and approved.
pub fn is_authorized(
  authorizer: Credential,
  extra_signatories: List<VerificationKeyHash>,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  when authorizer is {
    VerificationKey(hash) -> list.has(extra_signatories, hash)
    Script(_) -> pairs.has_key(withdrawals, authorizer)
  }
}

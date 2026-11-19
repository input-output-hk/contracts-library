//// Helpers for scripts that run under the withdraw-0 convention.
////
//// A withdraw-0 script runs as a reward withdrawal from its own stake
//// credential, and the ledger only accepts that withdrawal once the
//// credential is registered. Since Conway, registering a script credential
//// with the deposit-carrying certificate needs that script's approval through
//// its `publish` handler. The older certificate without a deposit field needs
//// no approval, but the Conway spec marks it for removal in a future era.

use cardano/certificate.{Certificate, RegisterCredential}

/// The `publish` policy for a withdraw-0 script: accept registering its stake
/// credential and refuse every other certificate.
///
/// Refusing deregistration keeps the credential registered for good, so no one
/// can deregister it and make every withdrawal that relies on it fail. The
/// deposit paid at registration is therefore never refunded. Refusing
/// delegation costs nothing: the credential holds no stake.
///
/// The ledger only asks a script to approve certificates for its own
/// credential, so there is no need to check whose credential it is.
pub fn accept_registration(certificate: Certificate) -> Bool {
  when certificate is {
    RegisterCredential { .. } -> True
    _ -> False
  }
}

//// Test-only authorizer scripts for the script-credential (withdraw-0) path.
//// NOT part of the library. Compiled to CBOR and embedded in
//// `e2e/src/fixtures.ts`; this project only exists to regenerate them.

use cardano/address.{Credential}
use cardano/script_context.{ScriptContext}
use cardano/transaction.{Transaction}

/// Approves every purpose. Used as an always-approving beneficiary/locker.
validator always_true {
  else(_ctx: ScriptContext) {
    True
  }
}

/// Rejects withdrawals (so a withdraw-0 authorization fails) but approves
/// everything else, so its stake credential can still be registered.
validator reject_withdraw {
  withdraw(_redeemer: Data, _account: Credential, _self: Transaction) {
    False
  }

  else(_ctx: ScriptContext) {
    True
  }
}

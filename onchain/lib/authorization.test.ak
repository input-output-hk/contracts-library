use authorization.{is_authorized}
use cardano/address.{Script, VerificationKey}

const vkh = #"11111111111111111111111111111111111111111111111111111111"

const script_hash = #"22222222222222222222222222222222222222222222222222222222"

test vkey_authorized_by_signature() {
  is_authorized(VerificationKey(vkh), [vkh], [])
}

test vkey_rejected_without_signature() fail {
  is_authorized(VerificationKey(vkh), [], [])
}

test script_authorized_by_withdrawal() {
  is_authorized(Script(script_hash), [], [Pair(Script(script_hash), 0)])
}

test script_rejected_without_withdrawal() fail {
  // A mere signature does not satisfy a *script* authorizer.
  is_authorized(Script(script_hash), [vkh], [])
}

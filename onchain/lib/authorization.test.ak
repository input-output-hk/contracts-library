use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{VerificationKeyHash}
use aiken/fuzz
use authorization.{is_authorized}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{Lovelace}
use cardano/fuzz as cardano_fuzz

// --------------------------------------------------------------- properties

fn auth_scenario() -> Fuzzer<
  (Credential, List<VerificationKeyHash>, Pairs<Credential, Lovelace>),
> {
  fuzz.tuple3(
    cardano_fuzz.credential(),
    fuzz.list(cardano_fuzz.verification_key_hash()),
    cardano_fuzz.withdrawals(),
  )
}

test prop_is_authorized_matches_credential(
  (credential, signers, withdrawals) via auth_scenario(),
) {
  fuzz.label_if(
    @"key",
    when credential is {
      VerificationKey(_) -> True
      _ -> False
    },
  )
  fuzz.label_if(
    @"script",
    when credential is {
      Script(_) -> True
      _ -> False
    },
  )
  let expected = when credential is {
    VerificationKey(hash) -> list.has(signers, hash)
    Script(_) -> pairs.has_key(withdrawals, credential)
  }
  is_authorized(credential, signers, withdrawals) == expected
}

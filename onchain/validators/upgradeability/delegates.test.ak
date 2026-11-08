use cardano/address.{Script, from_script}
use cardano/certificate.{
  Certificate, DelegateBlockProduction, DelegateCredential,
  RegisterAndDelegateCredential, RegisterCredential, UnregisterCredential,
}
use cardano/transaction.{placeholder}
use upgradeability/counter_logic
use upgradeability/counter_migration

const settings_policy =
  #"11111111111111111111111111111111111111111111111111111111"

const settings_token_name = "registry"

const own_hash = #"22222222222222222222222222222222222222222222222222222222"

const v2_hash = #"33333333333333333333333333333333333333333333333333333333"

const pool = #"44444444444444444444444444444444444444444444444444444444"

fn logic_publish(certificate: Certificate) -> Bool {
  let redeemer: Data = 0
  counter_logic.counter_logic.publish(
    settings_policy,
    settings_token_name,
    redeemer,
    certificate,
    placeholder,
  )
}

fn migration_publish(certificate: Certificate) -> Bool {
  let redeemer: Data = 0
  counter_migration.counter_migration.publish(
    settings_policy,
    settings_token_name,
    from_script(v2_hash),
    redeemer,
    certificate,
    placeholder,
  )
}

fn register() -> Certificate {
  RegisterCredential { credential: Script(own_hash), deposit: Never }
}

fn unregister() -> Certificate {
  UnregisterCredential { credential: Script(own_hash), refund: Never }
}

fn delegate() -> Certificate {
  DelegateCredential {
    credential: Script(own_hash),
    delegate: DelegateBlockProduction(pool),
  }
}

fn register_and_delegate() -> Certificate {
  RegisterAndDelegateCredential {
    credential: Script(own_hash),
    delegate: DelegateBlockProduction(pool),
    deposit: 2_000_000,
  }
}

test logic_accepts_stake_registration() {
  logic_publish(register())
}

test logic_rejects_stake_deregistration() {
  !logic_publish(unregister())
}

test logic_rejects_delegation() {
  !logic_publish(delegate())
}

test logic_rejects_registration_with_delegation() {
  !logic_publish(register_and_delegate())
}

test migration_accepts_stake_registration() {
  migration_publish(register())
}

test migration_rejects_stake_deregistration() {
  !migration_publish(unregister())
}

test migration_rejects_delegation() {
  !migration_publish(delegate())
}

test migration_rejects_registration_with_delegation() {
  !migration_publish(register_and_delegate())
}

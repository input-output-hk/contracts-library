use aiken/fuzz
use cardano/address.{
  Address, Script, from_script, from_verification_key, with_delegation_key,
  with_delegation_script,
}
use cardano/assets
use cardano/fuzz as cardano_fuzz
use cardano/transaction.{InlineDatum, NoDatum, Output, Transaction, placeholder}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/full_recipient_list_logic.{
  no_denied_recipients, only_allowed_recipients,
}

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const alice_key = #"11111111111111111111111111111111111111111111111111111111"

const bob_key = #"22222222222222222222222222222222222222222222222222222222"

const stake_key = #"33333333333333333333333333333333333333333333333333333333"

fn alice() -> Address {
  from_verification_key(alice_key)
}

fn bob() -> Address {
  from_verification_key(bob_key)
}

/// Alice's payment credential under a different stake delegation: a distinct
/// full address from `alice()`.
fn alice_with_stake() -> Address {
  with_delegation_key(from_verification_key(alice_key), stake_key)
}

/// The wallet address with a stake delegation: same payment credential as the
/// wallet, hence exempt from both checks.
fn wallet_address_with_stake() -> Address {
  with_delegation_script(from_script(wallet_policy), stake_key)
}

fn wallet_output() -> Output {
  Output {
    address: from_script(wallet_policy),
    value: assets.zero,
    datum: InlineDatum(WalletDatum { spenders: [], depositors: [] }),
    reference_script: None,
  }
}

fn payout(address: Address) -> Output {
  Output {
    address,
    value: assets.from_lovelace(1_000_000),
    datum: NoDatum,
    reference_script: None,
  }
}

fn tx_with(outputs: List<Output>) -> Transaction {
  Transaction { ..placeholder, outputs }
}

fn allowed_payout(tx: Transaction) -> Bool {
  only_allowed_recipients(tx, Script(wallet_policy), [alice()])
}

fn denied_payout(tx: Transaction) -> Bool {
  no_denied_recipients(tx, Script(wallet_policy), [alice()])
}

// ------------------------------------------------- only_allowed_recipients

test allow_allows_multiple_listed_payouts() {
  only_allowed_recipients(
    tx_with([wallet_output(), payout(alice()), payout(bob())]),
    Script(wallet_policy),
    [alice(), bob()],
  )
}

test allow_rejects_partially_listed_payouts() fail {
  allowed_payout(tx_with([wallet_output(), payout(alice()), payout(bob())]))
}

test allow_empty_list_rejects_any_payout() fail {
  only_allowed_recipients(
    tx_with([wallet_output(), payout(bob())]),
    Script(wallet_policy),
    [],
  )
}

test allow_continuation_only_passes() {
  allowed_payout(tx_with([wallet_output()]))
}

test allow_requires_exact_address() fail {
  allowed_payout(tx_with([wallet_output(), payout(alice_with_stake())]))
}

test allow_exempts_wallet_payment_credential() {
  allowed_payout(
    tx_with([wallet_output(), payout(wallet_address_with_stake())]),
  )
}

// -------------------------------------------------- no_denied_recipients

test deny_allows_unlisted_payout() {
  denied_payout(tx_with([wallet_output(), payout(bob())]))
}

test deny_empty_list_allows_any_payout() {
  no_denied_recipients(
    tx_with([wallet_output(), payout(alice())]),
    Script(wallet_policy),
    [],
  )
}

test deny_rejects_any_denied_payout() fail {
  denied_payout(tx_with([wallet_output(), payout(alice()), payout(bob())]))
}

test deny_matches_exact_address_only() {
  denied_payout(tx_with([wallet_output(), payout(alice_with_stake())]))
}

test deny_exempts_wallet_address() {
  no_denied_recipients(
    tx_with([wallet_output()]),
    Script(wallet_policy),
    [from_script(wallet_policy)],
  )
}

// --------------------------------------------------------------- properties

fn non_wallet_address() -> Fuzzer<Address> {
  fuzz.such_that(
    cardano_fuzz.address(),
    fn(address) { address.payment_credential != Script(wallet_policy) },
  )
}

test prop_allow_empty_rejects_payout(address via non_wallet_address()) {
  !only_allowed_recipients(
    tx_with([wallet_output(), payout(address)]),
    Script(wallet_policy),
    [],
  )
}

test prop_allow_listed_accepts(address via non_wallet_address()) {
  only_allowed_recipients(
    tx_with([wallet_output(), payout(address)]),
    Script(wallet_policy),
    [address],
  )
}

test prop_deny_listed_rejects(address via non_wallet_address()) {
  !no_denied_recipients(
    tx_with([wallet_output(), payout(address)]),
    Script(wallet_policy),
    [address],
  )
}

test prop_deny_empty_allows(address via non_wallet_address()) {
  no_denied_recipients(
    tx_with([wallet_output(), payout(address)]),
    Script(wallet_policy),
    [],
  )
}

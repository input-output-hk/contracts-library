use cardano/address.{
  Address, Credential, Inline, Pointer, Script, VerificationKey, from_script,
}
use cardano/assets
use cardano/transaction.{InlineDatum, NoDatum, Output, Transaction, placeholder}
use smart_wallet/types.{WalletDatum}
use smart_wallet/withdrawal_scripts/payment_staking_list_logic.{
  no_denied_recipients, only_allowed_recipients,
}

const wallet_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const payer1 = #"11111111111111111111111111111111111111111111111111111111"

const payer2 = #"22222222222222222222222222222222222222222222222222222222"

const payer3 = #"33333333333333333333333333333333333333333333333333333333"

const staker1 = #"44444444444444444444444444444444444444444444444444444444"

const staker2 = #"55555555555555555555555555555555555555555555555555555555"

fn address_with_stake(payment: Credential, stake: Credential) -> Address {
  Address { payment_credential: payment, stake_credential: Some(Inline(stake)) }
}

fn address_without_stake(payment: Credential) -> Address {
  Address { payment_credential: payment, stake_credential: None }
}

fn address_with_pointer_stake(payment: Credential) -> Address {
  Address {
    payment_credential: payment,
    stake_credential: Some(
      Pointer { slot_number: 1, transaction_index: 0, certificate_index: 0 },
    ),
  }
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
  only_allowed_recipients(
    tx,
    Script(wallet_policy),
    [VerificationKey(payer1)],
    [VerificationKey(staker1)],
  )
}

fn denied_payout(tx: Transaction) -> Bool {
  no_denied_recipients(
    tx,
    Script(wallet_policy),
    [VerificationKey(payer1)],
    [VerificationKey(staker1)],
  )
}

// ------------------------------------------------- only_allowed_recipients

test allow_listed_payment_and_staking() {
  allowed_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker1)),
        ),
      ],
    ),
  )
}

test allow_rejects_unlisted_staking() fail {
  allowed_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker2)),
        ),
      ],
    ),
  )
}

test allow_rejects_unlisted_payment() fail {
  allowed_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker1)),
        ),
      ],
    ),
  )
}

test allow_empty_allowed_payments_permits_any_payment() {
  only_allowed_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker1)),
        ),
      ],
    ),
    Script(wallet_policy),
    [],
    [VerificationKey(staker1)],
  )
}

test allow_empty_allowed_stakings_permits_any_staking() {
  only_allowed_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker2)),
        ),
      ],
    ),
    Script(wallet_policy),
    [VerificationKey(payer1)],
    [],
  )
}

test allow_empty_lists_permit_all() {
  only_allowed_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker2)),
        ),
      ],
    ),
    Script(wallet_policy),
    [],
    [],
  )
}

test allow_rejects_missing_staking_credential() fail {
  allowed_payout(
    tx_with(
      [wallet_output(), payout(address_without_stake(VerificationKey(payer1)))],
    ),
  )
}

test allow_rejects_pointer_staking_credential() fail {
  allowed_payout(
    tx_with(
      [
        wallet_output(),
        payout(address_with_pointer_stake(VerificationKey(payer1))),
      ],
    ),
  )
}

test allow_missing_staking_ok_when_stakings_empty() {
  only_allowed_recipients(
    tx_with(
      [wallet_output(), payout(address_without_stake(VerificationKey(payer1)))],
    ),
    Script(wallet_policy),
    [VerificationKey(payer1)],
    [],
  )
}

test allow_matches_script_payment_credential() {
  only_allowed_recipients(
    tx_with(
      [
        wallet_output(),
        payout(address_with_stake(Script(payer3), VerificationKey(staker1))),
      ],
    ),
    Script(wallet_policy),
    [Script(payer3)],
    [VerificationKey(staker1)],
  )
}

test allow_wallet_output_exempt() {
  allowed_payout(tx_with([wallet_output()]))
}

test allow_rejects_one_unlisted_payout() fail {
  allowed_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker1)),
        ),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker1)),
        ),
      ],
    ),
  )
}

// -------------------------------------------------- no_denied_recipients

test deny_rejects_denied_payment() fail {
  denied_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker2)),
        ),
      ],
    ),
  )
}

test deny_rejects_denied_staking() fail {
  denied_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker1)),
        ),
      ],
    ),
  )
}

test deny_allows_unlisted_payment_and_staking() {
  denied_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker2)),
        ),
      ],
    ),
  )
}

test deny_empty_denied_payments_permits_any_payment() {
  no_denied_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker2)),
        ),
      ],
    ),
    Script(wallet_policy),
    [],
    [VerificationKey(staker1)],
  )
}

test deny_empty_denied_stakings_permits_any_staking() {
  no_denied_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker2)),
        ),
      ],
    ),
    Script(wallet_policy),
    [VerificationKey(payer1)],
    [],
  )
}

test deny_empty_lists_permit_all() {
  no_denied_recipients(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker1)),
        ),
      ],
    ),
    Script(wallet_policy),
    [],
    [],
  )
}

test deny_missing_staking_credential_not_denied() {
  denied_payout(
    tx_with(
      [wallet_output(), payout(address_without_stake(VerificationKey(payer2)))],
    ),
  )
}

test deny_pointer_staking_credential_not_denied() {
  denied_payout(
    tx_with(
      [
        wallet_output(),
        payout(address_with_pointer_stake(VerificationKey(payer2))),
      ],
    ),
  )
}

test deny_wallet_output_exempt() {
  no_denied_recipients(
    tx_with([wallet_output()]),
    Script(wallet_policy),
    [Script(wallet_policy)],
    [VerificationKey(staker1)],
  )
}

test deny_rejects_one_denied_payout() fail {
  denied_payout(
    tx_with(
      [
        wallet_output(),
        payout(
          address_with_stake(VerificationKey(payer2), VerificationKey(staker2)),
        ),
        payout(
          address_with_stake(VerificationKey(payer1), VerificationKey(staker2)),
        ),
      ],
    ),
  )
}

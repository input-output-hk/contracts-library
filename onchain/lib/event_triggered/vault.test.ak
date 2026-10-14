// Tests for the vault validator (spec §3.1, §4.2 VaultDeposit, §4.6 Redeem).

use cardano/address.{from_script, from_verification_key}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/schedule
use event_triggered/types.{
  Payout, Redeem, VaultAction, VaultDatum, VaultDeposit, VaultParams,
}
use event_triggered/vault

// --------------------------------------------------------------- fixtures

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const vault_script = #"44444444444444444444444444444444444444444444444444444444"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const principal = 1000

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn params() -> VaultParams {
  VaultParams { principal }
}

fn datum() -> VaultDatum {
  VaultDatum { cnt_policy }
}

fn vault_input(index: Int, ada: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(vault_script),
      value: assets.from_lovelace(ada),
      datum: InlineDatum(datum()),
      reference_script: None,
    },
  }
}

fn own_ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn vault_output(ada: Int) -> Output {
  Output {
    address: from_script(vault_script),
    value: assets.from_lovelace(ada),
    datum: InlineDatum(datum()),
    reference_script: None,
  }
}

fn wallet_output(ada: Int) -> Output {
  Output {
    address: from_verification_key(holder_key),
    value: assets.from_lovelace(ada),
    datum: NoDatum,
    reference_script: None,
  }
}

fn check(action: VaultAction, self: Transaction) -> Bool {
  vault.validate(action, Some(datum()), own_ref(0), self, params())
}

// ------------------------------------------------------------------ deposit

test deposit_ok() {
  check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000)],
      outputs: [vault_output(5_000_000 + principal)],
    },
  )
}

test deposit_rejects_wrong_gain() {
  !check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000)],
      outputs: [vault_output(5_000_000 + principal - 1)],
    },
  )
}

test deposit_rejects_datum_change() {
  let tampered = Output {
    ..vault_output(5_000_000 + principal),
    datum: InlineDatum(
      VaultDatum {
        cnt_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      },
    ),
  }
  !check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000)],
      outputs: [tampered],
    },
  )
}

// ------------------------------------------------------------------- redeem

fn redeem_tx(payout_amount: Int, include_payout: Bool) -> Transaction {
  let outs = if include_payout {
    [vault_output(10_000_000 - 1000), wallet_output(payout_amount)]
  } else {
    [vault_output(10_000_000 - 1000)]
  }
  Transaction {
    ..placeholder,
    inputs: [vault_input(0, 10_000_000)],
    outputs: outs,
    mint: assets.from_asset(cnt_policy, schedule.encode_amount(1000), -1),
  }
}

test redeem_ok() {
  check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: 1000 },
      ],
    },
    redeem_tx(1000, True),
  )
}

test redeem_rejects_wrong_total() {
  !check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: 999 },
      ],
    },
    redeem_tx(999, True),
  )
}

test redeem_rejects_missing_payout() {
  !check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: 1000 },
      ],
    },
    redeem_tx(1000, False),
  )
}

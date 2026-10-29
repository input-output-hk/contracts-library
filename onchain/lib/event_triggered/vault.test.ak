// Tests for the vault validator (spec §3.1, §4.2 VaultDeposit, §4.6 Redeem,
// I10 vault identity).

use aiken/fuzz
use cardano/address.{from_script, from_verification_key}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/schedule
use event_triggered/types.{
  Payout, Redeem, VaultAction, VaultDatum, VaultDeposit, VaultParams, VaultTopUp,
}
use event_triggered/vault

// --------------------------------------------------------------- fixtures

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const vault_script = #"44444444444444444444444444444444444444444444444444444444"

const vault_nft_cs = #"99999999999999999999999999999999999999999999999999999999"

const vault_nft_name = "V0"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const principal = 1000

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn params() -> VaultParams {
  VaultParams { principal, vault_nft_cs }
}

fn datum() -> VaultDatum {
  VaultDatum { cnt_policy }
}

fn vault_value(ada: Int, with_nft: Bool) -> assets.Value {
  if with_nft {
    assets.from_lovelace(ada)
      |> assets.merge(assets.from_asset(vault_nft_cs, vault_nft_name, 1))
  } else {
    assets.from_lovelace(ada)
  }
}

fn vault_input(index: Int, ada: Int, with_nft: Bool) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(vault_script),
      value: vault_value(ada, with_nft),
      datum: InlineDatum(datum()),
      reference_script: None,
    },
  }
}

fn own_ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn vault_output(ada: Int, with_nft: Bool) -> Output {
  Output {
    address: from_script(vault_script),
    value: vault_value(ada, with_nft),
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
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [vault_output(5_000_000 + principal, True)],
    },
  )
}

test deposit_rejects_wrong_gain() {
  !check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [vault_output(5_000_000 + principal - 1, True)],
    },
  )
}

test deposit_rejects_datum_change() {
  let tampered = Output {
    ..vault_output(5_000_000 + principal, True),
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
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [tampered],
    },
  )
}

test deposit_rejects_without_nft() {
  !check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000, False)],
      outputs: [vault_output(5_000_000 + principal, False)],
    },
  )
}

// ------------------------------------------------------------------- top-up

test top_up_ok() {
  check(
    VaultTopUp,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [vault_output(8_000_000, True)],
    },
  )
}

test top_up_rejects_no_gain() {
  !check(
    VaultTopUp,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [vault_output(5_000_000, True)],
    },
  )
}

test top_up_rejects_loss() {
  !check(
    VaultTopUp,
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 5_000_000, True)],
      outputs: [vault_output(4_999_999, True)],
    },
  )
}

test top_up_rejects_removing_native_asset() {
  !check(
    VaultTopUp,
    Transaction {
      ..placeholder,
      inputs: [
        Input {
          ..vault_input(0, 5_000_000, True),
          output: with_stray(vault_input(0, 5_000_000, True).output),
        },
      ],
      outputs: [vault_output(8_000_000, True)],
    },
  )
}

// ------------------------------------------------------------------- redeem

fn redeem_tx(payout_amount: Int, include_payout: Bool) -> Transaction {
  let outs = if include_payout {
    [vault_output(10_000_000 - 1000, True), wallet_output(payout_amount)]
  } else {
    [vault_output(10_000_000 - 1000, True)]
  }
  Transaction {
    ..placeholder,
    inputs: [vault_input(0, 10_000_000, True)],
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

test redeem_rejects_without_nft() {
  !check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: 1000 },
      ],
    },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, False)],
      outputs: [vault_output(10_000_000 - 1000, False), wallet_output(1000)],
      mint: assets.from_asset(cnt_policy, schedule.encode_amount(1000), -1),
    },
  )
}

test redeem_rejects_two_vaults() {
  !check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: 1000 },
      ],
    },
    Transaction {
      ..placeholder,
      inputs: [
        vault_input(0, 10_000_000, True),
        vault_input(1, 10_000_000, True),
      ],
      outputs: [vault_output(10_000_000 - 1000, True), wallet_output(1000)],
      mint: assets.from_asset(cnt_policy, schedule.encode_amount(1000), -1),
    },
  )
}

// --------------------------------------------------- payout accounting
//
// Payouts are aggregated per address and matched against the aggregate ADA
// paid to that address, excluding the vault continuation; every payout and
// the redeemed total are positive; and the vault's non-ADA assets are
// carried through unchanged.

const recipient_key =
  #"77777777777777777777777777777777777777777777777777777777"

const stray_policy = #"88888888888888888888888888888888888888888888888888888888"

fn pay(key: ByteArray, amount: Int) -> Payout {
  Payout { address: from_verification_key(key), amount }
}

fn paid_to(key: ByteArray, ada: Int) -> Output {
  Output {
    address: from_verification_key(key),
    value: assets.from_lovelace(ada),
    datum: NoDatum,
    reference_script: None,
  }
}

fn burn(amount: Int) -> assets.Value {
  assets.from_asset(cnt_policy, schedule.encode_amount(amount), -1)
}

fn with_stray(output: Output) -> Output {
  Output {
    ..output,
    value: output.value |> assets.add(stray_policy, "stray", 1),
  }
}

// Sanity: a split payout to two distinct addresses is admitted.
test redeem_ok_split_between_two_addresses() {
  check(
    Redeem { payouts: [pay(holder_key, 600), pay(recipient_key, 400)] },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, True)],
      outputs: [
        vault_output(10_000_000 - 1000, True),
        paid_to(holder_key, 600),
        paid_to(recipient_key, 400),
      ],
      mint: burn(1000),
    },
  )
}

// Two payouts to the same address must be met by 1000 in aggregate, not by
// one 500 output counted twice.
test redeem_rejects_duplicate_payouts_sharing_one_output() {
  !check(
    Redeem { payouts: [pay(recipient_key, 500), pay(recipient_key, 500)] },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, True)],
      outputs: [
        vault_output(10_000_000 - 1000, True),
        paid_to(recipient_key, 500),
        paid_to(holder_key, 500),
      ],
      mint: burn(1000),
    },
  )
}

// A payout naming the vault's own address must not be satisfied by the
// vault continuation.
test redeem_rejects_payout_met_by_vault_continuation() {
  !check(
    Redeem {
      payouts: [Payout { address: from_script(vault_script), amount: 1000 }],
    },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, True)],
      outputs: [vault_output(10_000_000 - 1000, True), wallet_output(1000)],
      mint: burn(1000),
    },
  )
}

// Negative entries must not offset an inflated payout.
test redeem_rejects_non_positive_payout() {
  !check(
    Redeem { payouts: [pay(holder_key, 1500), pay(recipient_key, -500)] },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, True)],
      outputs: [
        vault_output(10_000_000 - 1000, True),
        paid_to(holder_key, 1500),
        paid_to(recipient_key, 2_000_000),
      ],
      mint: burn(1000),
    },
  )
}

// A redemption must redeem something.
test redeem_rejects_zero_value() {
  !check(
    Redeem { payouts: [] },
    Transaction {
      ..placeholder,
      inputs: [vault_input(0, 10_000_000, True)],
      outputs: [vault_output(10_000_000, True)],
    },
  )
}

// ------------------------------------------------- non-ADA preservation

test redeem_rejects_removing_native_asset() {
  !check(
    Redeem { payouts: [pay(holder_key, 1000)] },
    Transaction {
      ..placeholder,
      inputs: [
        Input {
          ..vault_input(0, 10_000_000, True),
          output: with_stray(vault_input(0, 10_000_000, True).output),
        },
      ],
      outputs: [
        vault_output(10_000_000 - 1000, True),
        with_stray(paid_to(holder_key, 1000)),
      ],
      mint: burn(1000),
    },
  )
}

test redeem_ok_preserving_native_asset() {
  check(
    Redeem { payouts: [pay(holder_key, 1000)] },
    Transaction {
      ..placeholder,
      inputs: [
        Input {
          ..vault_input(0, 10_000_000, True),
          output: with_stray(vault_input(0, 10_000_000, True).output),
        },
      ],
      outputs: [
        with_stray(vault_output(10_000_000 - 1000, True)),
        paid_to(holder_key, 1000),
      ],
      mint: burn(1000),
    },
  )
}

test deposit_rejects_removing_native_asset() {
  !check(
    VaultDeposit,
    Transaction {
      ..placeholder,
      inputs: [
        Input {
          ..vault_input(0, 5_000_000, True),
          output: with_stray(vault_input(0, 5_000_000, True).output),
        },
      ],
      outputs: [vault_output(5_000_000 + principal, True)],
    },
  )
}

// --------------------------------------------------------------- properties

test prop_deposit_exact_principal(
  (input_ada, gain) via fuzz.tuple(
    fuzz.int_between(0, 10_000_000),
    fuzz.int_between(0, 1_000_000),
  ),
) {
  let tx = Transaction {
    ..placeholder,
    inputs: [vault_input(0, input_ada, True)],
    outputs: [vault_output(input_ada + gain, True)],
  }
  let expected = gain == principal
  fuzz.label_if(@"exact", expected)
  fuzz.label_if(@"wrong-gain", !expected)
  check(VaultDeposit, tx) == expected
}

test prop_top_up_positive_gain(
  (input_ada, gain) via fuzz.tuple(
    fuzz.int_between(0, 10_000_000),
    fuzz.int_between(0, 1_000_000),
  ),
) {
  let tx = Transaction {
    ..placeholder,
    inputs: [vault_input(0, input_ada, True)],
    outputs: [vault_output(input_ada + gain, True)],
  }
  let expected = gain > 0
  fuzz.label_if(@"gain", expected)
  fuzz.label_if(@"no-gain", !expected)
  check(VaultTopUp, tx) == expected
}

test prop_redeem_conservation(
  (burned, payout) via fuzz.tuple(
    fuzz.int_between(1, 1_000_000),
    fuzz.int_between(0, 1_000_000),
  ),
) {
  let tx = Transaction {
    ..placeholder,
    inputs: [vault_input(0, 10_000_000, True)],
    outputs: [vault_output(10_000_000 - burned, True), wallet_output(payout)],
    mint: burn(burned),
  }
  let expected = payout == burned
  fuzz.label_if(@"exact", expected)
  fuzz.label_if(@"mismatch", !expected)
  check(
    Redeem {
      payouts: [
        Payout { address: from_verification_key(holder_key), amount: payout },
      ],
    },
    tx,
  ) == expected
}

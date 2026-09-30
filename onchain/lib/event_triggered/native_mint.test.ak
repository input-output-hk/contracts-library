// Minimum flow tests for the graduated asset's native mint policy (§4.5).
// Fixture style mirrors `lib/dao/proposal/proposal.test.ak`.

use aiken/interval
use cardano/address.{Address, from_script, with_delegation_key}
use cardano/assets
use cardano/transaction.{
  Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/native_mint
use event_triggered/types.{NativeMintParams, ScheduleStep}

// ------------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const native_policy =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const plb_script = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const owner1_key = #"55555555555555555555555555555555555555555555555555555555"

const principal_name = "BOND"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn schedule() -> List<ScheduleStep> {
  [
    ScheduleStep { deadline: 1000, value: 1040 },
    ScheduleStep { deadline: 2000, value: 1081 },
    ScheduleStep { deadline: 3000, value: 1124 },
    ScheduleStep { deadline: 4000, value: 1169 },
  ]
}

fn params() -> NativeMintParams {
  NativeMintParams {
    cip_policy,
    principal_name,
    scale: 1000,
    schedule: schedule(),
  }
}

fn plb_holder(key: ByteArray) -> Address {
  from_script(plb_script) |> with_delegation_key(key)
}

fn principal_holder_input(index: Int, key: ByteArray, qty: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: plb_holder(key),
      value: assets.from_asset(cip_policy, principal_name, qty)
        |> assets.merge(assets.from_lovelace(2_000_000)),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn enterprise_holder_input(index: Int, qty: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(plb_script),
      value: assets.from_asset(cip_policy, principal_name, qty)
        |> assets.merge(assets.from_lovelace(2_000_000)),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn native_tx(native_qty: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [principal_holder_input(0, owner1_key, 1000)],
    mint: assets.from_asset(cip_policy, principal_name, -1000)
      |> assets.merge(
          assets.from_asset(native_policy, principal_name, native_qty),
        ),
    validity_range: interval.after(4000),
  }
}

fn check(self: Transaction) -> Bool {
  native_mint.validate(self, native_policy, params())
}

// ------------------------------------------------------------------- tests

test native_mint_ok() {
  // exact scaled mirror: 1000 × 1169 / 1000
  check(native_tx(1169))
}

test rejects_wrong_amount() {
  !check(native_tx(1170))
}

test rejects_without_burn() {
  // no governed burn → nothing to back the mint
  !check(
    Transaction {
      ..placeholder,
      inputs: [principal_holder_input(0, owner1_key, 1000)],
      mint: assets.from_asset(native_policy, principal_name, 1169),
      validity_range: interval.after(4000),
    },
  )
}

test rejects_wrong_name() {
  !check(
    Transaction {
      ..placeholder,
      inputs: [principal_holder_input(0, owner1_key, 1000)],
      mint: assets.from_asset(cip_policy, principal_name, -1000)
        |> assets.merge(assets.from_asset(native_policy, "OTHER", 1169)),
      validity_range: interval.after(4000),
    },
  )
}

test rejects_burn_back() {
  // the graduated asset can never be burned through this policy
  !check(
    Transaction {
      ..placeholder,
      inputs: [principal_holder_input(0, owner1_key, 1000)],
      mint: assets.from_asset(cip_policy, principal_name, -1000)
        |> assets.merge(assets.from_asset(native_policy, principal_name, -1169)),
      validity_range: interval.after(4000),
    },
  )
}

test rejects_no_inline_holder() fail {
  // a holding input without an inline stake credential fails closed
  !check(
    Transaction {
      ..placeholder,
      inputs: [enterprise_holder_input(0, 1000)],
      mint: assets.from_asset(cip_policy, principal_name, -1000)
        |> assets.merge(assets.from_asset(native_policy, principal_name, 1169)),
      validity_range: interval.after(4000),
    },
  )
}

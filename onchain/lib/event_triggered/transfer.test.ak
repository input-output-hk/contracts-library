// Tests for the transfer logic (spec §4.3 name monotonicity, §4.4 opt-in,
// §4.5 claim, §4.7 retirement).

use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script, with_delegation_key,
}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/schedule
use event_triggered/transfer
use event_triggered/types.{CertificateDatum, RegistryNode, TransferParams}

// --------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const other_cnt = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const node_policy = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const plb_script = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const transfer_script =
  #"22222222222222222222222222222222222222222222222222222222"

const minting_script =
  #"11111111111111111111111111111111111111111111111111111111"

const third_party_script =
  #"33333333333333333333333333333333333333333333333333333333"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const other_key = #"88888888888888888888888888888888888888888888888888888888"

const pay_key = #"77777777777777777777777777777777777777777777777777777777"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn params() -> TransferParams {
  TransferParams { registry_node_cs: node_policy }
}

fn account() -> Credential {
  Script(transfer_script)
}

fn check(self: Transaction) -> Bool {
  transfer.validate(account(), self, params())
}

fn node_output() -> Output {
  Output {
    address: from_script(node_policy),
    value: assets.from_asset(node_policy, cip_policy, 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(
      RegistryNode {
        key: cip_policy,
        next: cip_policy,
        minting_logic_script: Script(minting_script),
        transfer_logic_script: Script(transfer_script),
        third_party_logic_script: Script(third_party_script),
        unfracking_logic_script: VerificationKey(#""),
        global_state_cs: #"",
      },
    ),
    reference_script: None,
  }
}

fn node_reference() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: 90,
    },
    output: node_output(),
  }
}

fn plb(stake: ByteArray) -> Address {
  from_script(plb_script) |> with_delegation_key(stake)
}

fn cert_datum(
  start: Int,
  commit: Option<Credential>,
  cnt: ByteArray,
) -> CertificateDatum {
  CertificateDatum { start, commit, cnt_policy: cnt }
}

fn cert_value(k: Int) -> assets.Value {
  assets.from_asset(cip_policy, schedule.step_name(k), 1)
    |> assets.merge(assets.from_lovelace(2_000_000))
}

fn cert_output(stake: ByteArray, k: Int, d: CertificateDatum) -> Output {
  Output {
    address: plb(stake),
    value: cert_value(k),
    datum: InlineDatum(d),
    reference_script: None,
  }
}

fn cert_input(
  index: Int,
  stake: ByteArray,
  k: Int,
  d: CertificateDatum,
) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: cert_output(stake, k, d),
  }
}

fn move_tx(
  k_in: Int,
  d_in: CertificateDatum,
  k_out: Int,
  d_out: CertificateDatum,
  stake_out: ByteArray,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, k_in, d_in)],
    reference_inputs: [node_reference()],
    outputs: [cert_output(stake_out, k_out, d_out)],
  }
}

// ----------------------------------------------------------------- transfers

test plain_transfer_ok() {
  let d = cert_datum(2000, None, cnt_policy)
  check(move_tx(0, d, 0, d, other_key))
}

test plain_transfer_clears_commit_on_owner_change() {
  check(
    move_tx(
      0,
      cert_datum(2000, Some(VerificationKey(pay_key)), cnt_policy),
      0,
      cert_datum(2000, None, cnt_policy),
      other_key,
    ),
  )
}

test plain_transfer_rejects_stale_commit_on_owner_change() {
  let d = cert_datum(2000, Some(VerificationKey(pay_key)), cnt_policy)
  !check(move_tx(0, d, 0, d, other_key))
}

test self_transfer_sets_commit_ok() {
  check(
    move_tx(
      0,
      cert_datum(2000, None, cnt_policy),
      0,
      cert_datum(2000, Some(VerificationKey(pay_key)), cnt_policy),
      holder_key,
    ),
  )
}

test transfer_rejects_start_change() {
  let d = cert_datum(2000, None, cnt_policy)
  !check(move_tx(0, d, 0, cert_datum(1999, None, cnt_policy), holder_key))
}

test transfer_rejects_cnt_change() {
  let d = cert_datum(2000, None, cnt_policy)
  !check(move_tx(0, d, 0, cert_datum(2000, None, other_cnt), holder_key))
}

test claim_ok() {
  let d = cert_datum(2000, None, cnt_policy)
  check(move_tx(0, d, 1, d, holder_key))
}

test claim_rejects_stake_change() {
  let d = cert_datum(2000, None, cnt_policy)
  !check(move_tx(0, d, 1, d, other_key))
}

test rejects_name_jump() {
  let d = cert_datum(2000, None, cnt_policy)
  !check(move_tx(0, d, 2, d, holder_key))
}

test retirement_requires_burn() {
  let d = cert_datum(2000, None, cnt_policy)
  let base = Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, 4, d)],
    reference_inputs: [node_reference()],
    outputs: [],
  }
  and {
    check(
      Transaction {
        ..base,
        mint: assets.from_asset(cip_policy, schedule.step_name(4), -1),
      },
    ),
    !check(base),
  }
}

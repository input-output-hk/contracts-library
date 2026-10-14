// Tests for the minting logic (spec §4.1 Register, §4.2 Deposit, §4.5 Advance,
// §4.7 Retire). Fixture style mirrors the other `*.test.ak` modules.

use aiken/interval
use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script, with_delegation_key,
}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/issuance
use event_triggered/schedule
use event_triggered/types.{
  Advance, CertificateDatum, Deposit, MintingAction, MintingParams, Register,
  RegistryNode, Retire, VaultDatum,
}

// --------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const other_cnt = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const node_policy = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const plb_script = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const minting_script =
  #"11111111111111111111111111111111111111111111111111111111"

const transfer_script =
  #"22222222222222222222222222222222222222222222222222222222"

const third_party_script =
  #"33333333333333333333333333333333333333333333333333333333"

const vault_script = #"44444444444444444444444444444444444444444444444444444444"

const issuer_key = #"55555555555555555555555555555555555555555555555555555555"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const pay_key = #"77777777777777777777777777777777777777777777777777777777"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const principal = 1000

fn params() -> MintingParams {
  MintingParams {
    registry_node_cs: node_policy,
    issuer: VerificationKey(issuer_key),
    transfer_logic: transfer_script,
    third_party_logic: third_party_script,
    vault: vault_script,
    principal,
  }
}

fn account() -> Credential {
  Script(minting_script)
}

fn check(action: MintingAction, self: Transaction) -> Bool {
  issuance.validate(action, account(), self, params())
}

fn node_datum() -> RegistryNode {
  RegistryNode {
    key: cip_policy,
    next: cip_policy,
    minting_logic_script: Script(minting_script),
    transfer_logic_script: Script(transfer_script),
    third_party_logic_script: Script(third_party_script),
    unfracking_logic_script: VerificationKey(#""),
    global_state_cs: #"",
  }
}

fn node_output() -> Output {
  Output {
    address: from_script(node_policy),
    value: assets.from_asset(node_policy, cip_policy, 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(node_datum()),
    reference_script: None,
  }
}

fn as_reference(index: Int, output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output,
  }
}

fn node_reference() -> Input {
  as_reference(90, node_output())
}

fn plb(stake: ByteArray) -> Address {
  from_script(plb_script) |> with_delegation_key(stake)
}

fn vault_addr() -> Address {
  from_script(vault_script)
}

fn vault_datum() -> VaultDatum {
  VaultDatum { cnt_policy }
}

fn vault_input(index: Int, ada: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: vault_addr(),
      value: assets.from_lovelace(ada),
      datum: InlineDatum(vault_datum()),
      reference_script: None,
    },
  }
}

fn vault_output(ada: Int) -> Output {
  Output {
    address: vault_addr(),
    value: assets.from_lovelace(ada),
    datum: InlineDatum(vault_datum()),
    reference_script: None,
  }
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

fn coupon(amount: Int, qty: Int) -> assets.Value {
  assets.from_asset(cnt_policy, schedule.encode_amount(amount), qty)
}

// ----------------------------------------------------------------- Register

test register_ok() {
  check(
    Register,
    Transaction {
      ..placeholder,
      outputs: [node_output()],
      mint: assets.from_asset(node_policy, cip_policy, 1),
      extra_signatories: [issuer_key],
    },
  )
}

test register_rejects_without_issuer() {
  !check(
    Register,
    Transaction {
      ..placeholder,
      outputs: [node_output()],
      mint: assets.from_asset(node_policy, cip_policy, 1),
    },
  )
}

test register_rejects_token_mint() {
  !check(
    Register,
    Transaction {
      ..placeholder,
      outputs: [
        node_output(),
        cert_output(holder_key, 0, cert_datum(2000, None, cnt_policy)),
      ],
      mint: assets.from_asset(node_policy, cip_policy, 1)
        |> assets.merge(cert_value(0)),
      extra_signatories: [issuer_key],
    },
  )
}

// ------------------------------------------------------------------ Deposit

fn deposit_tx(d: CertificateDatum, gain: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [vault_input(0, 5_000_000)],
    reference_inputs: [node_reference()],
    outputs: [vault_output(5_000_000 + gain), cert_output(holder_key, 0, d)],
    mint: assets.from_asset(cip_policy, schedule.step_name(0), 1),
    validity_range: interval.between(1000, 2000),
  }
}

test deposit_ok() {
  check(Deposit, deposit_tx(cert_datum(2000, None, cnt_policy), principal))
}

test deposit_rejects_wrong_start() {
  !check(Deposit, deposit_tx(cert_datum(999, None, cnt_policy), principal))
}

test deposit_rejects_commit() {
  !check(
    Deposit,
    deposit_tx(
      cert_datum(2000, Some(VerificationKey(pay_key)), cnt_policy),
      principal,
    ),
  )
}

test deposit_rejects_wrong_gain() {
  !check(Deposit, deposit_tx(cert_datum(2000, None, cnt_policy), principal - 1))
}

test deposit_rejects_cnt_mismatch() {
  !check(Deposit, deposit_tx(cert_datum(2000, None, other_cnt), principal))
}

// ------------------------------------------------------------------ Advance

fn advance_tx(
  commit: Option<Credential>,
  signers: List<ByteArray>,
  coupon_qty: Int,
) -> Transaction {
  let d = cert_datum(2000, commit, cnt_policy)
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, 0, d)],
    reference_inputs: [node_reference()],
    outputs: [cert_output(holder_key, 1, d)],
    mint: assets.from_asset(cip_policy, schedule.step_name(0), -1)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1))
      |> assets.merge(coupon(1040, coupon_qty)),
    extra_signatories: signers,
  }
}

test advance_owner_ok() {
  check(Advance, advance_tx(None, [holder_key], 1))
}

test advance_issuer_ok() {
  check(Advance, advance_tx(Some(VerificationKey(pay_key)), [issuer_key], 1))
}

test advance_rejects_unauthorized() {
  !check(Advance, advance_tx(None, [], 1))
}

test advance_rejects_missing_coupon() {
  !check(Advance, advance_tx(None, [holder_key], 0))
}

test advance_rejects_datum_change() {
  !check(
    Advance,
    Transaction {
      ..advance_tx(None, [holder_key], 1),
      outputs: [cert_output(holder_key, 1, cert_datum(999, None, cnt_policy))],
    },
  )
}

test advance_rejects_cert_stake_change() {
  let d = cert_datum(2000, None, cnt_policy)
  !check(
    Advance,
    Transaction {
      ..advance_tx(None, [holder_key], 1),
      outputs: [cert_output(issuer_key, 1, d)],
    },
  )
}

// ------------------------------------------------------------------- Retire

fn retire_tx(coupon_qty: Int) -> Transaction {
  let d = cert_datum(2000, None, cnt_policy)
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, 4, d)],
    reference_inputs: [node_reference()],
    outputs: [],
    mint: assets.from_asset(cip_policy, schedule.step_name(4), -1)
      |> assets.merge(coupon(principal, coupon_qty)),
    extra_signatories: [holder_key],
  }
}

test retire_ok() {
  check(Retire, retire_tx(1))
}

test retire_issuer_ok() {
  check(
    Retire,
    Transaction {
      ..retire_tx(1),
      inputs: [
        cert_input(
          0,
          holder_key,
          4,
          cert_datum(2000, Some(VerificationKey(pay_key)), cnt_policy),
        ),
      ],
      extra_signatories: [issuer_key],
    },
  )
}

test retire_rejects_missing_coupon() {
  !check(Retire, retire_tx(0))
}

test retire_rejects_continuation() {
  !check(
    Retire,
    Transaction {
      ..retire_tx(1),
      outputs: [cert_output(holder_key, 4, cert_datum(2000, None, cnt_policy))],
    },
  )
}

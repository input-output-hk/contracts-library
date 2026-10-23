// Tests for the issuer-triggered third-party logic (spec §4.5, §4.7, I9).

use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script,
  from_verification_key, with_delegation_key,
}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/schedule
use event_triggered/third_party
use event_triggered/types.{CertificateDatum, RegistryNode, ThirdPartyParams}

// --------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const node_policy = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const plb_script = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const transfer_script =
  #"22222222222222222222222222222222222222222222222222222222"

const minting_script =
  #"11111111111111111111111111111111111111111111111111111111"

const third_party_script =
  #"33333333333333333333333333333333333333333333333333333333"

const issuer_key = #"55555555555555555555555555555555555555555555555555555555"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const pay_key = #"77777777777777777777777777777777777777777777777777777777"

const principal = 1000

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn params() -> ThirdPartyParams {
  ThirdPartyParams {
    registry_node_cs: node_policy,
    issuer: VerificationKey(issuer_key),
  }
}

fn account() -> Credential {
  Script(third_party_script)
}

fn check(self: Transaction) -> Bool {
  third_party.validate(account(), self, params())
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

fn cert_datum(start: Int, commit: Option<Credential>) -> CertificateDatum {
  CertificateDatum { start, commit, cnt_policy }
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

fn coupon_output(payment: ByteArray, amount: Int) -> Output {
  Output {
    address: from_verification_key(payment),
    value: assets.from_asset(cnt_policy, schedule.encode_amount(amount), 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: NoDatum,
    reference_script: None,
  }
}

fn coupon(amount: Int) -> assets.Value {
  assets.from_asset(cnt_policy, schedule.encode_amount(amount), 1)
}

// -------------------------------------------------------------------- claim

fn claim_tx(
  commit: Option<Credential>,
  signers: List<ByteArray>,
  pay: ByteArray,
) -> Transaction {
  let d = cert_datum(2000, commit)
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, 0, d)],
    reference_inputs: [node_reference()],
    outputs: [cert_output(holder_key, 1, d), coupon_output(pay, 1040)],
    mint: assets.from_asset(cip_policy, schedule.step_name(0), -1)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1))
      |> assets.merge(coupon(1040)),
    extra_signatories: signers,
  }
}

test claim_ok() {
  check(claim_tx(Some(VerificationKey(pay_key)), [issuer_key], pay_key))
}

test claim_rejects_without_issuer() {
  !check(claim_tx(Some(VerificationKey(pay_key)), [], pay_key))
}

test claim_rejects_without_commit() {
  !check(claim_tx(None, [issuer_key], pay_key))
}

test claim_rejects_redirect() {
  !check(claim_tx(Some(VerificationKey(pay_key)), [issuer_key], holder_key))
}

test claim_rejects_missing_coupon() {
  let d = cert_datum(2000, Some(VerificationKey(pay_key)))
  !check(
    Transaction {
      ..claim_tx(Some(VerificationKey(pay_key)), [issuer_key], pay_key),
      outputs: [cert_output(holder_key, 1, d)],
      mint: assets.from_asset(cip_policy, schedule.step_name(0), -1)
        |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1)),
    },
  )
}

test claim_rejects_datum_change() {
  !check(
    Transaction {
      ..claim_tx(Some(VerificationKey(pay_key)), [issuer_key], pay_key),
      outputs: [
        cert_output(
          holder_key,
          1,
          cert_datum(999, Some(VerificationKey(pay_key))),
        ),
        coupon_output(pay_key, 1040),
      ],
    },
  )
}

// --------------------------------------------------------------- graduation

fn graduation_tx(signers: List<ByteArray>, pay: ByteArray) -> Transaction {
  let d = cert_datum(2000, Some(VerificationKey(pay_key)))
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, holder_key, 4, d)],
    reference_inputs: [node_reference()],
    outputs: [coupon_output(pay, principal)],
    mint: assets.from_asset(cip_policy, schedule.step_name(4), -1)
      |> assets.merge(coupon(principal)),
    extra_signatories: signers,
  }
}

test graduation_ok() {
  check(graduation_tx([issuer_key], pay_key))
}

test graduation_rejects_redirect() {
  !check(graduation_tx([issuer_key], holder_key))
}

test graduation_rejects_without_issuer() {
  !check(graduation_tx([], pay_key))
}

test graduation_rejects_continuation() {
  let d = cert_datum(2000, Some(VerificationKey(pay_key)))
  !check(
    Transaction {
      ..graduation_tx([issuer_key], pay_key),
      outputs: [
        cert_output(holder_key, 4, d),
        coupon_output(pay_key, principal),
      ],
    },
  )
}

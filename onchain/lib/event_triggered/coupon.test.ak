// Tests for one vault's coupon policy (spec §3.2, §4.5 scheduled,
// §4.7 graduation, burns).

use aiken/fuzz
use aiken/interval
use cardano/address.{Address, VerificationKey, from_script, with_delegation_key}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/coupon
use event_triggered/schedule
use event_triggered/types.{CertificateDatum, CouponParams}

// --------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const cnt_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const plb_script = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const holder_key = #"66666666666666666666666666666666666666666666666666666666"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const interval = 1000

const principal = 1000

fn params() -> CouponParams {
  CouponParams {
    cip_policy,
    principal,
    interval,
    amounts: [1040, 1081, 1124, 1169],
  }
}

fn check(self: Transaction) -> Bool {
  coupon.validate(self, cnt_policy, params())
}

fn plb() -> Address {
  from_script(plb_script) |> with_delegation_key(holder_key)
}

fn cert_datum(start: Int) -> CertificateDatum {
  CertificateDatum { start, commit: None, cnt_policy }
}

fn cert_value(k: Int) -> assets.Value {
  assets.from_asset(cip_policy, schedule.step_name(k), 1)
    |> assets.merge(assets.from_lovelace(2_000_000))
}

fn cert_output(k: Int, start: Int) -> Output {
  Output {
    address: plb(),
    value: cert_value(k),
    datum: InlineDatum(cert_datum(start)),
    reference_script: None,
  }
}

fn cert_input(index: Int, k: Int, start: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: cert_output(k, start),
  }
}

fn coupon(amount: Int) -> assets.Value {
  assets.from_asset(cnt_policy, schedule.encode_amount(amount), 1)
}

// ------------------------------------------------------------------ scheduled

fn scheduled_tx(
  name_amount: Int,
  cert_out: Option<Output>,
  lower: Int,
) -> Transaction {
  let outs: List<Output> = when cert_out is {
    Some(o) -> [o]
    None -> []
  }
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, 0, 2000)],
    outputs: outs,
    mint: coupon(name_amount)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(0), -1))
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1)),
    validity_range: interval.after(lower),
  }
}

test scheduled_ok() {
  check(scheduled_tx(1040, Some(cert_output(1, 2000)), 3000))
}

test scheduled_rejects_early() {
  !check(scheduled_tx(1040, Some(cert_output(1, 2000)), 2999))
}

test scheduled_rejects_wrong_amount() {
  !check(scheduled_tx(1081, Some(cert_output(1, 2000)), 3000))
}

test graduation_ok() {
  check(
    Transaction {
      ..placeholder,
      inputs: [cert_input(0, 4, 2000)],
      outputs: [],
      mint: coupon(principal)
        |> assets.merge(
            assets.from_asset(cip_policy, schedule.step_name(4), -1),
          ),
      validity_range: interval.after(6000),
    },
  )
}

test graduation_rejects_early() {
  !check(
    Transaction {
      ..placeholder,
      inputs: [cert_input(0, 4, 2000)],
      outputs: [],
      mint: coupon(principal)
        |> assets.merge(
            assets.from_asset(cip_policy, schedule.step_name(4), -1),
          ),
      validity_range: interval.after(5999),
    },
  )
}

test graduation_rejects_wrong_amount() {
  !check(
    Transaction {
      ..placeholder,
      inputs: [cert_input(0, 4, 2000)],
      outputs: [],
      mint: coupon(1040)
        |> assets.merge(
            assets.from_asset(cip_policy, schedule.step_name(4), -1),
          ),
      validity_range: interval.after(6000),
    },
  )
}

// --------------------------------------------------------------------- burns

test burns_are_admitted() {
  check(
    Transaction {
      ..placeholder,
      mint: assets.from_asset(cnt_policy, schedule.encode_amount(1040), -1),
    },
  )
}

test rejects_two_positive_names() {
  !check(
    Transaction {
      ..placeholder,
      mint: coupon(1040) |> assets.merge(coupon(1081)),
    },
  )
}

// ------------------------------------------- certificate/policy binding
//
// A positive coupon mint is admitted only for a certificate whose datum
// selects this policy (`cnt_policy == own_policy`). Without that binding a
// certificate of vault A, advanced or retired legitimately under A's policy,
// also authorizes coupons under every other vault's policy whose schedule
// conditions happen to hold, and those coupons redeem at the other vault.

const foreign_policy =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const issuer_pay_key =
  #"55555555555555555555555555555555555555555555555555555555"

/// A certificate UTxO selecting `selects` as its coupon policy.
fn cert_for(k: Int, selects: ByteArray, commit) -> Output {
  Output {
    address: plb(),
    value: cert_value(k),
    datum: InlineDatum(
      CertificateDatum { start: 2000, commit, cnt_policy: selects },
    ),
    reference_script: None,
  }
}

fn input_of(index: Int, output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output,
  }
}

fn foreign_coupon(amount: Int) -> assets.Value {
  assets.from_asset(foreign_policy, schedule.encode_amount(amount), 1)
}

/// Advance `0 -> 1` of a certificate selecting `selects`, minting step 1's
/// coupon under this policy plus `extra`.
fn advance_for(selects: ByteArray, commit, extra: assets.Value) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [input_of(0, cert_for(0, selects, commit))],
    outputs: [cert_for(1, selects, commit)],
    mint: coupon(1040)
      |> assets.merge(extra)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(0), -1))
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1)),
    validity_range: interval.after(3000),
  }
}

/// Retirement at the final step of a certificate selecting `selects`,
/// minting the principal coupon under this policy plus `extra`.
fn retire_for(selects: ByteArray, commit, extra: assets.Value) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [input_of(0, cert_for(4, selects, commit))],
    outputs: [],
    mint: coupon(principal)
      |> assets.merge(extra)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(4), -1)),
    validity_range: interval.after(6000),
  }
}

// Sanity: the same shapes pass when the certificate selects this policy.

test scheduled_ok_for_own_certificate() {
  check(advance_for(cnt_policy, None, assets.zero))
}

test graduation_ok_for_own_certificate() {
  check(retire_for(cnt_policy, None, assets.zero))
}

// Owner-path claims.

test scheduled_rejects_certificate_of_another_policy() {
  !check(advance_for(foreign_policy, None, assets.zero))
}

test graduation_rejects_certificate_of_another_policy() {
  !check(retire_for(foreign_policy, None, assets.zero))
}

// The realistic shape: the certificate's own coupon (under its policy) is
// minted as the issuance logic requires, and a second coupon is piggybacked
// under this policy in the same transaction.

test scheduled_rejects_piggyback_on_foreign_claim() {
  !check(advance_for(foreign_policy, None, foreign_coupon(1040)))
}

test graduation_rejects_piggyback_on_foreign_retirement() {
  !check(retire_for(foreign_policy, None, foreign_coupon(principal)))
}

// Issuer-triggered claims (the certificate commits a payment credential).

test scheduled_rejects_foreign_certificate_issuer_triggered() {
  !check(
    advance_for(
      foreign_policy,
      Some(VerificationKey(issuer_pay_key)),
      foreign_coupon(1040),
    ),
  )
}

test graduation_rejects_foreign_certificate_issuer_triggered() {
  !check(
    retire_for(
      foreign_policy,
      Some(VerificationKey(issuer_pay_key)),
      foreign_coupon(principal),
    ),
  )
}

// Burns stay unrestricted: a foreign certificate in the transaction does not
// block redeeming this policy's coupons.

test burns_admitted_alongside_foreign_certificate() {
  check(
    Transaction {
      ..placeholder,
      inputs: [input_of(0, cert_for(0, foreign_policy, None))],
      outputs: [cert_for(1, foreign_policy, None)],
      mint: assets.from_asset(cnt_policy, schedule.encode_amount(1040), -1)
        |> assets.merge(foreign_coupon(1040))
        |> assets.merge(
            assets.from_asset(cip_policy, schedule.step_name(0), -1),
          )
        |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1)),
      validity_range: interval.after(3000),
    },
  )
}

// --------------------------------------------------------------- properties

fn scheduled_tx_at(
  start: Int,
  name_amount: Int,
  cert_out: Option<Output>,
  lower: Int,
) -> Transaction {
  let outs: List<Output> = when cert_out is {
    Some(o) -> [o]
    None -> []
  }
  Transaction {
    ..placeholder,
    inputs: [cert_input(0, 0, start)],
    outputs: outs,
    mint: coupon(name_amount)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(0), -1))
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(1), 1)),
    validity_range: interval.after(lower),
  }
}

test prop_scheduled_coupon_deadline(
  (start, lower) via fuzz.tuple(
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 2_000_000),
  ),
) {
  let expected = lower >= start + interval
  fuzz.label_if(@"reached", expected)
  fuzz.label_if(@"early", !expected)
  check(scheduled_tx_at(start, 1040, Some(cert_output(1, start)), lower)) == expected
}

test prop_scheduled_coupon_wrong_amount(
  start via fuzz.int_between(0, 1_000_000),
) {
  !check(
    scheduled_tx_at(start, 1081, Some(cert_output(1, start)), start + interval),
  )
}

test prop_graduation_deadline(
  (start, lower) via fuzz.tuple(
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 2_000_000),
  ),
) {
  let tx = Transaction {
    ..placeholder,
    inputs: [cert_input(0, 4, start)],
    outputs: [],
    mint: coupon(principal)
      |> assets.merge(assets.from_asset(cip_policy, schedule.step_name(4), -1)),
    validity_range: interval.after(lower),
  }
  let expected = lower >= start + 4 * interval
  fuzz.label_if(@"reached", expected)
  fuzz.label_if(@"early", !expected)
  check(tx) == expected
}

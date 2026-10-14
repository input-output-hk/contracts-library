// Tests for one vault's coupon policy (spec §3.2, §4.5 scheduled,
// §4.7 graduation, burns).

use aiken/interval
use cardano/address.{Address, from_script, with_delegation_key}
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

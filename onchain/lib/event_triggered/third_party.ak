//// Third-party logic (withdraw-0) — the opt-in issuer trigger for the
//// event-triggered assets substandard (spec §4.5, §4.7, I9).
////
//// When a certificate's datum commits a payment credential (`commit`), the
//// issuer may advance or retire it through the third-party path. This
//// predicate:
////   * requires the issuer's authorisation;
////   * requires the exact certificate transition — the paired output carries
////     the next name with the same address and datum (a claim), or there is no
////     certificate continuation (a retirement); and
////   * binds the coupon minted under the certificate's `cnt_policy` to the
////     committed payment credential: every output carrying it must pay `pay`,
////     so the issuer can trigger but never redirect.
////
//// The coupon mint is also required by the minting logic's `Advance`/`Retire`
//// modes, so the trigger cannot skip it.
////
//// The governed policy id resolves at runtime from the referenced registry
//// node: it depends on the issuance credential, so this validator cannot bake
//// it.

use aiken/collection/dict
use aiken/collection/list
use authorization.{is_authorized}
use cardano/address.{Credential}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Input, Output, Transaction}
use event_triggered/certificate
use event_triggered/registry
use event_triggered/schedule
use event_triggered/types.{CertificateDatum, ThirdPartyParams}

pub fn validate(
  account: Credential,
  self: Transaction,
  params: ThirdPartyParams,
) -> Bool {
  let referenced = registry.outputs_of(self.reference_inputs)
  expect [(policy, _)] = registry.governing_third_party(
    referenced,
    params.registry_node_cs,
    account,
  )
  let certs_in = certificate.cert_inputs(self.inputs, policy)
  let certs_out = certificate.cert_outputs(self.outputs, policy)
  and {
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
    when certs_in is {
      [(input, k, d)] ->
        when d.commit is {
          Some(pay) -> and {
              transition(self, policy, input, k, d, certs_out),
              coupon_to_pay(self, d.cnt_policy, pay),
            }
          None -> False
        }
      _ -> False
    },
  }
}

/// The exact transition shape: a claim pairs the spent certificate with the
/// name `k+1` continuation (same address and datum), or a retirement leaves no
/// certificate continuation. In both cases the governed mint must balance.
fn transition(
  self: Transaction,
  policy: PolicyId,
  input: Input,
  k: Int,
  d: CertificateDatum,
  certs_out: List<(Output, Int, CertificateDatum)>,
) -> Bool {
  when certs_out is {
    [] ->
      dict.to_pairs(tokens(self.mint, policy)) == [
        Pair(schedule.step_name(k), -1),
      ]
    [(output, k_out, d_out)] -> and {
        k_out == k + 1,
        k_out <= 255,
        input.output.address == output.address,
        d_out == d,
        dict.to_pairs(tokens(self.mint, policy)) == [
          Pair(schedule.step_name(k), -1),
          Pair(schedule.step_name(k_out), 1),
        ],
      }
    _ -> False
  }
}

/// Exactly one positive coupon unit under the certificate's `cnt_policy`, and
/// every output carrying it pays `pay` (I9). This is also the presence rule:
/// the trigger must mint the coupon.
fn coupon_to_pay(self: Transaction, cnt: PolicyId, pay: Credential) -> Bool {
  when dict.to_pairs(tokens(self.mint, cnt)) is {
    [Pair(name, 1)] -> {
      let carriers = list.filter(
        self.outputs,
        fn(output) { quantity_of(output.value, cnt, name) > 0 },
      )
      !list.is_empty(carriers) && list.all(
        carriers,
        fn(output) { output.address.payment_credential == pay },
      )
    }
    _ -> False
  }
}

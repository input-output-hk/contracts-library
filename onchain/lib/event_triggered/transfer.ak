//// Transfer logic (withdraw-0) — step monotonicity for the event-triggered
//// assets substandard (spec §4.3, I7, I8).
////
//// The certificate is a CIP-113 token at the PLB; moving it moves the claim.
//// The core `transfer` validator already verified ownership, custody and value
//// containment, so this predicate adds only the claim-state rules: a
//// continuation must record the same `step` (plain transfer) or exactly
//// `step + 1` (the coupon claim, §4.4) — never less — and a certificate may
//// only be left without a continuation alongside its `cip_policy` burn (the
//// retirement shape, §4.6). Every certificate UTxO is held to exactly one
//// unit, so units cannot be merged or split.
////
//// The governed policy id resolves at runtime from the referenced registry
//// node: it depends on the issuance credential, so this validator cannot bake
//// it.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Output, Transaction}
use event_triggered/certificate
use event_triggered/registry
use event_triggered/types.{TransferParams}

pub fn validate(
  account: Credential,
  self: Transaction,
  params: TransferParams,
) -> Bool {
  let referenced = registry.outputs_of(self.reference_inputs)
  expect [(policy, _)] = registry.governing_transfer(
    referenced,
    params.registry_node_cs,
    account,
  )
  let inputs = certificate.cert_inputs(
    self.inputs,
    policy,
    params.certificate_name,
  )
  let outputs = certificate.cert_outputs(
    self.outputs,
    policy,
    params.certificate_name,
  )
  when inputs is {
    [input] -> {
      let unit_in = quantity_of(
        input.output.value,
        policy,
        params.certificate_name,
      ) == 1
      let unit_out = list.all(
        outputs,
        fn(output: Output) {
          quantity_of(output.value, policy, params.certificate_name) == 1
        },
      )
      and {
        unit_in,
        unit_out,
        when outputs is {
          [] -> retirement(self, policy)
          [output] -> step_monotone(input.output, output)
          _ -> False
        },
      }
    }
    // No certificate input, or more than one (a merge): reject.
    _ -> False
  }
}

/// Step monotonicity (I7): a continuation records the same `step` or exactly
/// `step + 1` — never less.
fn step_monotone(input: Output, output: Output) -> Bool {
  when (certificate.step_of(input), certificate.step_of(output)) is {
    (Some(before), Some(after)) -> after == before || after == before + 1
    _ -> False
  }
}

/// A certificate with no continuation is a retirement: the transaction must
/// carry a negative mint under the governed policy. The exact burn shape is
/// validated by the minting logic's `Retire` mode (§4.6).
fn retirement(self: Transaction, policy: PolicyId) -> Bool {
  tokens(self.mint, policy)
    |> dict.values
    |> list.any(fn(quantity) { quantity < 0 })
}

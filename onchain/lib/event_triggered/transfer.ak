//// Transfer logic (withdraw-0) — name monotonicity for the event-triggered
//// assets substandard (spec §4.3, I7, I8).
////
//// The certificate is a CIP-113 token at the PLB; moving it moves the claim.
//// The core `transfer` validator already verified ownership, custody and value
//// containment, so this predicate adds only the claim-state rules:
////   * a continuation keeps the step name (plain transfer / opting) — and may
////     change `commit` only on a self-transfer (same stake), clearing it on an
////     owner change — or advances by exactly one (the coupon claim, §4.5),
////     preserving the datum and the same owner; and
////   * `start` and `cnt_policy` never change.
//// A certificate may only be left without a continuation alongside its
//// `cip_policy` burn (the retirement shape, §4.7). Every certificate UTxO is
//// held to exactly one unit, so units cannot be merged or split.
////
//// The governed policy id resolves at runtime from the referenced registry
//// node: it depends on the issuance credential, so this validator cannot bake
//// it.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{Input, Output, Transaction}
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
  let certs_in = certificate.cert_inputs(self.inputs, policy)
  let certs_out = certificate.cert_outputs(self.outputs, policy)
  when (certs_in, certs_out) is {
    ([(_input, _k, _d)], []) -> retirement(self, policy)
    ([(input, k, d)], [(output, k_out, d_out)]) -> and {
        d_out.start == d.start,
        d_out.cnt_policy == d.cnt_policy,
        or {
          // Plain transfer or opt-in/out: the name is preserved. `commit` may
          // change only when the stake credential does not (a self-transfer);
          // on an owner change it must be cleared.
          and {
            k_out == k,
            or {
              same_stake(input, output),
              d_out.commit == None,
            },
          },
          // Coupon claim: the name advances by exactly one, same owner, and
          // the datum is preserved. The coupon itself is required by the
          // minting logic's `Advance` mode (I3).
          and {
            k_out == k + 1,
            k_out <= 255,
            same_stake(input, output),
            d_out.commit == d.commit,
          },
        },
      }
    // No certificate input, or more than one (a merge): reject.
    _ -> False
  }
}

/// Is the continuation staked to the same owner?
fn same_stake(input: Input, output: Output) -> Bool {
  input.output.address.stake_credential == output.address.stake_credential
}

/// A certificate with no continuation is a retirement: the transaction must
/// carry a negative mint under the governed policy. The exact burn shape,
/// final step, maturity window and principal coupon are validated by the
/// minting logic's `Retire` mode and the coupon policy (§4.7).
fn retirement(self: Transaction, policy: PolicyId) -> Bool {
  tokens(self.mint, policy)
    |> dict.values
    |> list.any(fn(quantity) { quantity < 0 })
}

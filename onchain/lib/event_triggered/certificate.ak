//// Certificate helpers for the event-triggered assets substandard: locating
//// certificate UTxOs and decoding their inline `step` datum (spec §3.3, I8).
////
//// Every certificate UTxO carries exactly one unit of the certificate asset
//// under the governed policy; ownership is its inline stake credential. These
//// helpers scan inputs/outputs without positional assumptions.

use aiken/collection/list
use cardano/assets.{AssetName, PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output}
use event_triggered/types.{CertificateDatum}

/// Every input holding the certificate asset (quantity > 0).
pub fn cert_inputs(
  inputs: List<Input>,
  cip_policy: PolicyId,
  name: AssetName,
) -> List<Input> {
  list.filter(
    inputs,
    fn(input) { quantity_of(input.output.value, cip_policy, name) > 0 },
  )
}

/// Every output holding the certificate asset (quantity > 0).
pub fn cert_outputs(
  outputs: List<Output>,
  cip_policy: PolicyId,
  name: AssetName,
) -> List<Output> {
  list.filter(
    outputs,
    fn(output) { quantity_of(output.value, cip_policy, name) > 0 },
  )
}

/// Decode an output's inline datum as a certificate `{ step }`, or `None`.
pub fn step_of(output: Output) -> Option<Int> {
  when output.datum is {
    InlineDatum(data) -> {
      expect CertificateDatum { step }: CertificateDatum = data
      Some(step)
    }
    _ -> None
  }
}

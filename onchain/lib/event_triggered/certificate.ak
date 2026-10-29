//// Certificate helpers for the event-triggered assets substandard: locating
//// certificate UTxOs and decoding their inline state (spec §3.3, I8).
////
//// Every certificate UTxO carries exactly one unit of exactly one
//// step-shaped name under the governed policy; ownership is its inline stake
//// credential. These helpers scan inputs/outputs without positional
//// assumptions.

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{InlineDatum, Input, Output}
use event_triggered/schedule
use event_triggered/types.{CertificateDatum}

/// Parse an output as a certificate UTxO: exactly one unit of exactly one
/// step-shaped name under `policy`, with an inline `CertificateDatum`. Any
/// other shape under the policy is not a certificate (`None`).
pub fn cert_of(
  output: Output,
  policy: PolicyId,
) -> Option<(Int, CertificateDatum)> {
  when tokens(output.value, policy) |> dict.to_pairs() is {
    [Pair(name, 1)] ->
      when schedule.step_of_name(name) is {
        Some(k) ->
          when output.datum is {
            InlineDatum(data) -> {
              expect d: CertificateDatum = data
              Some((k, d))
            }
            _ -> None
          }
        None -> None
      }
    _ -> None
  }
}

/// Every input that parses as a certificate, as `(input, step, datum)`.
pub fn cert_inputs(
  inputs: List<Input>,
  policy: PolicyId,
) -> List<(Input, Int, CertificateDatum)> {
  list.filter_map(
    inputs,
    fn(input) {
      when cert_of(input.output, policy) is {
        Some((k, d)) -> Some((input, k, d))
        None -> None
      }
    },
  )
}

/// Every output that parses as a certificate, as `(output, step, datum)`.
pub fn cert_outputs(
  outputs: List<Output>,
  policy: PolicyId,
) -> List<(Output, Int, CertificateDatum)> {
  list.filter_map(
    outputs,
    fn(output) {
      when cert_of(output, policy) is {
        Some((k, d)) -> Some((output, k, d))
        None -> None
      }
    },
  )
}

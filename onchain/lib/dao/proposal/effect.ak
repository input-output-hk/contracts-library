//// Library for poll-effect scripts: the per-option validators referenced by a
//// proposal's `results` field.
////
//// A candidate script must not trust its caller. Being listed as an effect
//// (or even merely having its withdrawal included) says nothing about the
//// poll's outcome — the proposal validator only forces the *winner's* effect
//// to run; it cannot force losers to stay silent, and it cannot prevent a
//// tx from withdrawing from the script outside of `EndProposal`. Candidate
//// scripts therefore close the loop themselves with `am_i_the_winner`.
////
//// The verdict itself is proven by the proposal validator: an input sitting
//// behind the real validator's address (pinned via `proposal_policy`) that
//// is consumed with `EndProposal` has already been checked for a poll closed
//// past its tally deadline, a strict winner above the `execute` threshold,
//// and a `EndProposal { winner }` declaration matching the tally. A candidate
//// thus only needs to find the single proposal input of the transaction and
//// confirm its declaration names this very script. Exactly one proposal input
//// is required: two simultaneous polls naming the same script would make the
//// single approval ambiguous. The withdrawal redeemer is left entirely to the
//// candidate: it is the script's private interface, not part of the protocol.

use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/assets.{PolicyId, has_any_nft}
use cardano/transaction.{Input, Transaction}
use dao/types.{EndProposal, ProposalRedeemer}
use dao/utils.{spend_redeemer}

/// Does this transaction genuinely close exactly one poll whose declared
/// winner — as enforced by the pinned proposal validator — is this script?
/// Designed for candidates running under the withdraw-0 convention.
///
/// `proposal_policy` must be pinned at compile time (the proposal validator's
/// own hash); deriving it from transaction data would let anyone forge an
/// approving poll.
pub fn am_i_the_winner(
  proposal_policy: PolicyId,
  own_hash: ScriptHash,
  self: Transaction,
) -> Bool {
  let is_proposal = fn(input: Input) {
    let out = input.output
    has_any_nft(out.value, proposal_policy) && out.address.payment_credential == Script(
      proposal_policy,
    )
  }
  when list.filter(self.inputs, is_proposal) is {
    [input] -> {
      expect end: ProposalRedeemer = spend_redeemer(
        self,
        input.output_reference,
      )
      when end is {
        EndProposal{winner: Some(winner)} -> winner == own_hash
        _ -> False
      }
    }
    _ -> False
  }
}

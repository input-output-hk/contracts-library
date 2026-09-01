//// Reference example of a well-formed poll-effect candidate: one of the
//// per-option scripts a proposal can bind in its `results` field.
////
//// A candidate runs under the withdraw-0 convention and must not trust its
//// caller: being triggered (or even listed in `results`) proves nothing about
//// the poll's outcome. This example therefore guards its entire execution
//// with `am_i_the_winner`, which checks that the transaction closes exactly
//// one poll whose `EndProposal { winner }` declaration — already verified
//// against the tally by the pinned proposal validator — names this script.
//// Any additional business logic (transfers, mints, further authorizations)
//// composes on top of the verdict with `and`.
////
//// The withdrawal redeemer is the candidate's private interface: the protocol
//// never inspects it, so each candidate is free to declare whatever intent it
//// needs. This reference example carries no intent, hence `Data`.
////
//// `proposal_policy` (the proposal validator's own hash) is pinned at compile
//// time on purpose: deriving it from transaction data would let anyone forge
//// an approving poll.

use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use dao/proposal/effect.{am_i_the_winner}

validator poll_effect(proposal_policy: PolicyId) {
  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    expect Script(own_hash) = account
    am_i_the_winner(proposal_policy, own_hash, self)
  }

  else(_) {
    fail
  }
}

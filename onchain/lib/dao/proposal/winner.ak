//// Strict-winner resolution for a proposal's vote tally.
////
//// This single definition backs the proposal validator's own check in
//// `validate_end_proposal`: the tally-derived winner is what the
//// `EndProposal { winner }` redeemer declaration is measured against, and it
//// is the same enforcement poll-effect candidates rely on via
//// `am_i_the_winner`.

use aiken/collection/list
use aiken/option

/// The strictly-winning option and its vote total, or `None` on a tie / no votes.
pub fn winner(votes: List<Int>) -> Option<(Int, Int)> {
  let (best_option, best_votes, tie) = list.indexed_foldr(
    votes,
    (None, 0, False),
    fn(option, v, acc) {
      let (bo, bv, tie) = acc
      if v > bv {
        (Some(option), v, False)
      } else if v == bv {
        (bo, bv, True)
      } else {
        (bo, bv, tie)
      }
    },
  )
  best_option
    |> option.and_then(
        fn(option) {
          if !tie && best_votes > 0 {
            Some((option, best_votes))
          } else {
            None
          }
        },
      )
}

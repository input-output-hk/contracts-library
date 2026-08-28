//// Strict-winner resolution for a proposal's vote tally.
////
//// This single definition is shared by the proposal validator
//// (`validate_end_proposal`) and the poll-effect library (`am_i_the_winner`)
//// so neither can drift from the other's notion of "won".

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

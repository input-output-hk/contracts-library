//// Property-based tests for the strict-winner resolution.

use aiken/collection/list
use aiken/fuzz
use dao/proposal/winner.{winner}

fn votes_fuzzer() -> Fuzzer<List<Int>> {
  fuzz.list(fuzz.int_between(0, 1_000_000))
}

test prop_winner_is_strict_max(votes via votes_fuzzer()) {
  when winner(votes) is {
    Some((option, total)) -> and {
        list.at(votes, option) == Some(total),
        total > 0,
        list.indexed_foldr(
          votes,
          True,
          fn(index, value, ok) { ok && ( index == option || value < total ) },
        ),
      }
    None -> {
      let max_votes = list.foldl(
        votes,
        0,
        fn(value, acc) {
          if value > acc {
            value
          } else {
            acc
          }
        },
      )
      let max_count = list.foldl(
        votes,
        0,
        fn(value, acc) {
          if value == max_votes {
            acc + 1
          } else {
            acc
          }
        },
      )
      max_votes == 0 || max_count >= 2
    }
  }
}

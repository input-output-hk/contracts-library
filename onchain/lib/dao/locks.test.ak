use dao/locks.{free_stake, has_proposal, locked_stake, prune_expired}

const p1 = #"01"

const p2 = #"02"

const p3 = #"03"

// ----------------------------------------------------------------- prune

test prune_drops_expired_and_boundary() {
  // unlock_time <= now is expired; strictly-greater survives.
  let locks = [(p1, 100, 5), (p2, 200, 7), (p3, 150, 3)]
  prune_expired(locks, 150) == [(p2, 200, 7)]
}

test prune_keeps_all_when_future() {
  let locks = [(p1, 100, 5), (p2, 200, 7)]
  prune_expired(locks, 50) == locks
}

test prune_empty() {
  prune_expired([], 10) == []
}

// ----------------------------------------------------------------- locked

test locked_is_max_not_sum() {
  locked_stake([(p1, 100, 5), (p2, 200, 12), (p3, 150, 8)]) == 12
}

test locked_zero_when_empty() {
  locked_stake([]) == 0
}

// ----------------------------------------------------------------- free

test free_is_total_minus_max() {
  free_stake(20, [(p1, 100, 5), (p2, 200, 12)]) == 8
}

test free_equals_total_when_no_locks() {
  free_stake(20, []) == 20
}

// ----------------------------------------------------------------- has

test has_proposal_true() {
  has_proposal([(p1, 100, 5), (p2, 200, 12)], p2)
}

test has_proposal_false() {
  !has_proposal([(p1, 100, 5)], p2)
}

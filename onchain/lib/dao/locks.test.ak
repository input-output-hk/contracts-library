use aiken/collection/list
use aiken/fuzz
use dao/locks.{Lock, free_stake, has_proposal, locked_stake, prune_expired}

const p1 = #"01"

const p2 = #"02"

const p3 = #"03"

fn lock(proposal_id: ByteArray, unlock_time: Int, stake: Int) -> Lock {
  Lock { proposal_id, unlock_time, stake }
}

// ----------------------------------------------------------------- prune

test prune_drops_expired_and_boundary() {
  // unlock_time <= now is expired; strictly-greater survives.
  let locks = [lock(p1, 100, 5), lock(p2, 200, 7), lock(p3, 150, 3)]
  prune_expired(locks, 150) == [lock(p2, 200, 7)]
}

// ----------------------------------------------------------------- locked

test locked_is_max_not_sum() {
  locked_stake([lock(p1, 100, 5), lock(p2, 200, 12), lock(p3, 150, 8)]) == 12
}

// ----------------------------------------------------------------- free

test free_is_total_minus_max() {
  free_stake(20, [lock(p1, 100, 5), lock(p2, 200, 12)]) == 8
}

// ----------------------------------------------------------------- has

test has_proposal_true() {
  has_proposal([lock(p1, 100, 5), lock(p2, 200, 12)], p2)
}

test has_proposal_false() {
  !has_proposal([lock(p1, 100, 5)], p2)
}

// --------------------------------------------------------------- properties

fn lock_fuzzer() -> Fuzzer<Lock> {
  fuzz.map3(
    fuzz.bytearray(),
    fuzz.int_between(0, 1_000_000),
    fuzz.int_between(0, 1_000_000),
    fn(proposal_id, unlock_time, stake) {
      Lock { proposal_id, unlock_time, stake }
    },
  )
}

test prop_prune_only_unexpired(
  (locks, now) via fuzz.tuple(
    fuzz.list(lock_fuzzer()),
    fuzz.int_between(0, 1_000_000),
  ),
) {
  let pruned = prune_expired(locks, now)
  list.all(pruned, fn(lock) { lock.unlock_time > now }) && list.length(pruned) <= list.length(
    locks,
  )
}

test prop_prune_idempotent(
  (locks, now) via fuzz.tuple(
    fuzz.list(lock_fuzzer()),
    fuzz.int_between(0, 1_000_000),
  ),
) {
  prune_expired(prune_expired(locks, now), now) == prune_expired(locks, now)
}

test prop_locked_is_max(locks via fuzz.list(lock_fuzzer())) {
  let max = locked_stake(locks)
  if list.is_empty(locks) {
    max == 0
  } else {
    list.all(locks, fn(lock) { lock.stake <= max }) && list.any(
      locks,
      fn(lock) { lock.stake == max },
    )
  }
}

test prop_free_plus_locked(
  (total, locks) via fuzz.tuple(
    fuzz.int_between(0, 1_000_000),
    fuzz.list(lock_fuzzer()),
  ),
) {
  free_stake(total, locks) + locked_stake(locks) == total
}

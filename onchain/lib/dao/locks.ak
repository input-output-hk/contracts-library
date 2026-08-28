//// Stake-lock bookkeeping for the DAO stake position.
////
//// A lock is recorded when a stake position co-signs, creates, or votes on a
//// proposal. It prevents the same tokens from being reused before the
//// relevant proposal phase ends: while a lock is live, that much stake is
//// *frozen* and cannot be withdrawn.
////
//// The frozen amount is the **maximum** stake across live locks (not the sum),
//// because the same tokens back every concurrent action — a position with
//// `N` tokens can lend all `N` to several proposals at once. See
//// `docs/explorations/dao/transactions.typ` (Withdraw notes).

use aiken/collection/list

/// A single lock: proposal id, unlock time (POSIX ms), and the stake committed.
pub type Lock {
  Lock { proposal_id: ByteArray, unlock_time: Int, stake: Int }
}

/// Drop locks whose unlock time has passed (`unlock_time <= now`).
pub fn prune_expired(locks: List<Lock>, now: Int) -> List<Lock> {
  list.filter(locks, fn(lock) { lock.unlock_time > now })
}

/// The amount of stake currently frozen: the largest committed stake across
/// all locks (`0` when there are no locks).
pub fn locked_stake(locks: List<Lock>) -> Int {
  list.reduce(
    locks,
    0,
    fn(acc, lock) {
      if lock.stake > acc {
        lock.stake
      } else {
        acc
      }
    },
  )
}

/// Stake free to withdraw: `total` minus the frozen amount.
pub fn free_stake(total: Int, locks: List<Lock>) -> Int {
  total - locked_stake(locks)
}

/// Does any lock reference `proposal_id`?
pub fn has_proposal(locks: List<Lock>, proposal_id: ByteArray) -> Bool {
  list.any(locks, fn(lock) { lock.proposal_id == proposal_id })
}

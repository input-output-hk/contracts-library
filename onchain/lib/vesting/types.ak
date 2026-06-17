//// On-chain state and actions for the linear vesting contract.
//// See `specs/vesting/linear-vesting.md` §3.

use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}

/// One asset in a vesting bundle, paired with the **original** total quantity
/// that the schedule releases over its lifetime.
pub type VestedAsset {
  policy: PolicyId,
  name: AssetName,
  total: Int,
}

/// Immutable vesting state. Written once at lock time; every continuing output
/// must reproduce it verbatim. Times are POSIX **milliseconds**.
pub type VestingDatum {
  /// Who may claim. A key authorizes by signing; a script by being invoked.
  beneficiary: Credential,
  /// Who may recover the remainder after `recovery_time`. Same pluggable
  /// credential mechanism as `beneficiary`.
  locker: Credential,
  /// The original locked bundle and per-asset totals.
  vesting: List<VestedAsset>,
  start_time: Int,
  end_time: Int,
  /// After this time the `locker` may recover whatever remains. Must be
  /// strictly after `end_time` (enforced on cancel).
  recovery_time: Int,
}

/// Actions on a vesting UTxO.
pub type VestingRedeemer {
  /// Beneficiary withdraws up to the currently-vested amount.
  Claim
  /// Locker recovers the remainder once `recovery_time` has passed.
  Cancel
}

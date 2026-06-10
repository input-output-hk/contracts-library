//// Linear-vesting datum and redeemer types.
////
//// Faithful port of Anastasia Labs' `linear-vesting` (Plutarch) contract. The
//// validator is *not* parameterised — every vesting arrangement is fully
//// described by the datum of its locked UTxO, so multiple independent vestings
//// can coexist at the same script address.

use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}

/// A single fungible asset class (`policy_id`, `asset_name`) being vested.
/// Serialises as `#6.121([policy_id, asset_name])`, matching the reference
/// implementation's `AssetClass` encoding.
pub type VestingAsset {
  policy_id: PolicyId,
  asset_name: AssetName,
}

/// Configuration for one vesting arrangement.
///
/// After `first_unlock_possible_after` and before `vesting_period_end`, the
/// `beneficiary` may withdraw the vested asset in proportion to the elapsed
/// installments, returning the remainder to the script. After
/// `vesting_period_end`, the beneficiary may withdraw everything.
///
/// Field order matches the reference implementation so datums are
/// wire-compatible.
pub type VestingDatum {
  /// Who is allowed to claim. Authorisation is a signature from this address's
  /// payment credential (must be a verification-key credential).
  beneficiary: Address,
  /// The fungible token being vested (one asset class per UTxO).
  vesting_asset: VestingAsset,
  /// Total quantity placed under vesting at the start.
  total_vesting_qty: Int,
  /// POSIX time (ms) at which vesting begins.
  vesting_period_start: Int,
  /// POSIX time (ms) at which vesting completes; the full balance unlocks.
  vesting_period_end: Int,
  /// POSIX time (ms) before which no partial unlock is permitted.
  first_unlock_possible_after: Int,
  /// Number of discrete installments the period is divided into.
  total_installments: Int,
}

/// Redeemer for the vesting validator.
pub type VestingRedeemer {
  /// Withdraw the currently-vested portion, returning the remainder to the
  /// script with the datum intact.
  PartialUnlock
  /// Withdraw the entire remaining balance after `vesting_period_end`.
  FullUnlock
}

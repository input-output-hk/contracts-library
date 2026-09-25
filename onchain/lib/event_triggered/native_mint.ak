//// The graduated asset's native mint policy (spec §4.5, T4).
////
//// A **new** native policy, deliberately not 1:1 quantity-conserved
//// (Q-GRAD-1): graduation burns `N` principal tokens and mints exactly
//// `N × v4 / scale` under this policy — the scaled mirror of the burn at the
//// schedule's final value. The policy is **signer-agnostic**: it approves
//// the mint only against the governed burn of the same asset name under the
//// bond's `cip_policy` ("no burn CIP, no mint", scaled), whichever
//// credential signed the burn. The burn's own authorization — the `d4`
//// event gate, whole-holdings-per-name shape and owner-authorized
//// destination binding — is the minting logic's `Burn` mode, which the
//// presence of the negative `cip_policy` entry forces to run in the same
//// transaction: a negative mint under a policy means that policy's script
//// ran and approved exactly that mint.
////
//// The mint amount is the **sum of the per-owner floors**
//// (`schedule.total_payout` over the burned holdings) — the identical
//// computation the minting logic's Burn mode validates, so the two scripts
//// agree exactly. Rounding dust is never minted, so nobody gains from
//// batching graduations.
////
//// Burning the graduated asset back is not approved: the mint must be
//// positive. The policy governs nothing else — the graduated asset is a
//// plain native token at normal addresses once minted.

use aiken/collection/dict
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Transaction}
use event_triggered/schedule
use event_triggered/types.{NativeMintParams}

/// Approve the graduated asset's mint iff it is the exact scaled mirror of a
/// live burn of the same asset name under the bond policy. `own_policy` is
/// this policy's id, supplied by the `mint` handler.
pub fn validate(
  self: Transaction,
  own_policy: PolicyId,
  params: NativeMintParams,
) -> Bool {
  expect Some(final_value) = schedule.final_value(params.schedule)
  when tokens(self.mint, own_policy) |> dict.to_pairs() is {
    [Pair(name, quantity)] -> {
      let burned = quantity_of(
        self.mint,
        params.cip_policy,
        params.principal_name,
      )
      expect Some(holdings) = schedule.burned_holdings(
        self.inputs,
        params.cip_policy,
        params.principal_name,
      )
      and {
        // The mirrored name: the same asset name the burn consumed (§4.5).
        name == params.principal_name,
        // Mint, never burn-back; the backing burn must be live.
        quantity > 0,
        burned < 0,
        // Exactly `burned × v4 / scale`, per-owner floors summed — the same
        // number the minting logic's Burn mode derives.
        quantity == schedule.total_payout(holdings, final_value, params.scale),
      }
    }
    _ -> False
  }
}

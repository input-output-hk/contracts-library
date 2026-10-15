//// Vault validator for the event-triggered assets substandard — the ADA vaults
//// backing the tokenized bond (spec §3.1, §4.2, §4.6, I10).
////
//// A vault is an ADA UTxO whose inline datum binds the instrument's coupon
//// policy and which carries exactly one `vault_nft_cs` NFT (minted by the
//// deployment's authority at creation — creation is out of scope). The NFT is
//// the vault's identity: a script address alone authenticates nothing, so
//// every spend requires it and every continuation preserves it. There is
//// exactly one vault input and one continuation per transaction, so a
//// redemption can never mix two vaults.
////
//// Two spend paths:
////   * `VaultDeposit` (§4.2): a unit deposit must add exactly the baked
////     `principal` to the vault, carrying address, datum and NFT unchanged;
////     and
////   * `Redeem` (§4.6): burn-to-pay — the vault loses exactly the sum decoded
////     from the burned coupon names, paid to the addresses the redeemer names.
////
//// Owner custody (draining or topping up the vault) is the instrument's
//// central assumption and lives off-chain (§7); the owner funds the vault by
//// sending ADA to its address, which runs no validator.

use aiken/collection/list
use cardano/assets.{quantity_of}
use cardano/transaction.{Output, OutputReference, Transaction}
use event_triggered/schedule
use event_triggered/types.{
  Payout, Redeem, VaultAction, VaultDatum, VaultDeposit, VaultParams,
}
use event_triggered/vault_nft.{nft_of}

pub fn validate(
  redeemer: VaultAction,
  datum: Option<VaultDatum>,
  own_ref: OutputReference,
  self: Transaction,
  params: VaultParams,
) -> Bool {
  expect Some(VaultDatum { cnt_policy }) = datum
  let vins = list.filter(
    self.inputs,
    fn(input) { nft_of(input.output, params.vault_nft_cs) != None },
  )
  let vouts = list.filter(
    self.outputs,
    fn(output) { nft_of(output, params.vault_nft_cs) != None },
  )
  when (vins, vouts) is {
    // Exactly one vault input (the one being spent) and exactly one
    // continuation: a redemption can never touch two vaults (I10).
    ([vin], [vout]) ->
      when
        (
          nft_of(vin.output, params.vault_nft_cs),
          nft_of(vout, params.vault_nft_cs),
        )
      is {
        (Some(name), Some(name_out)) -> and {
            vin.output_reference == own_ref,
            name == name_out,
            // Address and datum are carried byte-for-byte.
            vin.output.address == vout.address,
            vin.output.datum == vout.datum,
            when redeemer is {
              VaultDeposit -> delta(vin.output, vout) == params.principal
              Redeem { payouts } -> {
                expect Some(burned) = schedule.total_burned(
                  self.mint,
                  cnt_policy,
                )
                and {
                  // Burn-to-pay exactness (I4): the vault loses exactly the
                  // redeemed value, no more and no less.
                  delta(vin.output, vout) == 0 - burned,
                  // The redeemer names the payouts and their total is the
                  // burned value.
                  payouts_total(payouts) == burned,
                  payouts_present(self.outputs, payouts),
                }
              }
            },
          }
        _ -> False
      }
    _ -> False
  }
}

/// The net ADA change of the vault pair: continuation minus spent input.
fn delta(input: Output, output: Output) -> Int {
  quantity_of(output.value, #"", #"") - quantity_of(input.value, #"", #"")
}

fn payouts_total(payouts: List<Payout>) -> Int {
  list.foldl(
    payouts,
    0,
    fn(payout: Payout, total: Int) { total + payout.amount },
  )
}

/// Every named payout lands at its address with at least the named amount.
fn payouts_present(outputs: List<Output>, payouts: List<Payout>) -> Bool {
  list.all(
    payouts,
    fn(payout: Payout) {
      list.any(
        outputs,
        fn(output: Output) {
          output.address == payout.address && quantity_of(
            output.value,
            #"",
            #"",
          ) >= payout.amount
        },
      )
    },
  )
}

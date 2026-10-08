//// Vault validator for the event-triggered assets substandard — the ADA vault
//// backing the tokenized bond (spec §3.1, §4.2, §4.5).
////
//// The vault is an ADA UTxO whose inline datum binds the instrument's coupon
//// policy. It has two spend paths:
////   * `Deposit` (§4.2): a unit deposit must add exactly the baked `principal`
////     to the vault, carrying the datum unchanged; and
////   * `Redeem` (§4.5): burn-to-pay — the vault loses exactly the sum decoded
////     from the burned coupon names, paid to the addresses the redeemer names,
////     with the datum carried unchanged.
////
//// Owner custody (draining or topping up the vault) is the instrument's
//// central assumption and lives off-chain (§7); the owner funds the vault by
//// sending ADA to its address, which runs no validator.

use aiken/collection/list
use cardano/address.{Address}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use event_triggered/schedule
use event_triggered/types.{
  Payout, Redeem, VaultAction, VaultDatum, VaultDeposit, VaultParams,
}

pub fn validate(
  redeemer: VaultAction,
  datum: Option<VaultDatum>,
  own_ref: OutputReference,
  self: Transaction,
  params: VaultParams,
) -> Bool {
  expect Some(VaultDatum { cnt_policy }) = datum
  let vault = spent_address(own_ref, self)
  when redeemer is {
    VaultDeposit -> and {
        net_gain(self.inputs, self.outputs, vault) == Some(params.principal),
        datum_preserved(self.outputs, vault, cnt_policy),
      }
    Redeem { payouts } -> {
      expect Some(burned) = schedule.total_burned(self.mint, cnt_policy)
      and {
        // Burn-to-pay exactness (I4): the vault loses exactly the redeemed
        // value, no more and no less.
        net_gain(self.inputs, self.outputs, vault) == Some(0 - burned),
        // The redeemer names the payouts and their total is the burned value.
        payouts_total(payouts) == burned,
        payouts_present(self.outputs, payouts),
        datum_preserved(self.outputs, vault, cnt_policy),
      }
    }
  }
}

/// The address of the vault UTxO being spent.
fn spent_address(own_ref: OutputReference, self: Transaction) -> Address {
  expect Some(input) = list.find(
    self.inputs,
    fn(input: Input) { input.output_reference == own_ref },
  )
  input.output.address
}

/// The net ADA change at the vault address across the transaction: outputs
/// minus inputs.
fn net_gain(
  inputs: List<Input>,
  outputs: List<Output>,
  vault: Address,
) -> Option<Int> {
  Some(ada_at_outputs(outputs, vault) - ada_at_inputs(inputs, vault))
}

fn ada_at_outputs(outputs: List<Output>, vault: Address) -> Int {
  list.foldl(
    outputs,
    0,
    fn(output: Output, total: Int) {
      if output.address == vault {
        total + quantity_of(output.value, #"", #"")
      } else {
        total
      }
    },
  )
}

fn ada_at_inputs(inputs: List<Input>, vault: Address) -> Int {
  list.foldl(
    inputs,
    0,
    fn(input: Input, total: Int) {
      if input.output.address == vault {
        total + quantity_of(input.output.value, #"", #"")
      } else {
        total
      }
    },
  )
}

/// Every vault output carries the same `cnt_policy` datum, and there is at
/// least one (the continuation).
fn datum_preserved(
  outputs: List<Output>,
  vault: Address,
  cnt_policy: PolicyId,
) -> Bool {
  let vault_outputs = list.filter(
    outputs,
    fn(output: Output) { output.address == vault },
  )
  !list.is_empty(vault_outputs) && list.all(
    vault_outputs,
    fn(output: Output) {
      when output.datum is {
        InlineDatum(data) -> {
          expect VaultDatum { cnt_policy: c }: VaultDatum = data
          c == cnt_policy
        }
        _ -> False
      }
    },
  )
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

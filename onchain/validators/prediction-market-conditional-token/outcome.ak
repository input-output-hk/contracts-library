use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use prediction_market_conditional_token/types.{
  BeaconMintAction, MintBeacon, OutcomeDatum, OutcomeRedeemer, Resolve,
  TokenInfo,
}

validator outcome(market_address: Address, setup_fee: TokenInfo) {
  spend(
    datum: Option<OutcomeDatum>,
    redeemer: OutcomeRedeemer,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    expect Some(outcome_datum) = datum
    when redeemer is {
      Resolve { winner: _ } -> True
    }
  }

  mint(redeemer: BeaconMintAction, _policy_id: PolicyId, _self: Transaction) {
    when redeemer is {
      MintBeacon { market_id: _ } -> True
    }
  }

  else(_) {
    fail
  }

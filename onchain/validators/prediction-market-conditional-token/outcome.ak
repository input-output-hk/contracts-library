use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use prediction_market_conditional_token/types.{
  BeaconMintAction, MintBeacon, OutcomeDatum, OutcomeRedeemer, Resolve,
  TokenInfo,
}

validator outcome(_protocol_address: Address, _setup_fee: TokenInfo) {
  spend(
    datum: Option<OutcomeDatum>,
    redeemer: OutcomeRedeemer,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    expect Some(_outcome_datum) = datum
    let Resolve { winner: _ } = redeemer
    True
  }

  mint(redeemer: BeaconMintAction, _policy_id: PolicyId, _self: Transaction) {
    let MintBeacon { market_id: _ } = redeemer
    True
  }

  else(_) {
    fail
  }
}

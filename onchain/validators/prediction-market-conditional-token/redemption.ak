use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use prediction_market_conditional_token/types.{
  BurnCompleteSet, BurnSet, BurnWinner, ClaimDraw, ClaimTimeout, MintAction,
  MintSet, RedeemWinner, RedemptionDatum, RedemptionRedeemer, SweepResidual,
  TokenInfo,
}

validator redemption(_protocol_address: Address, _market_fee: TokenInfo) {
  spend(
    datum: Option<RedemptionDatum>,
    redeemer: RedemptionRedeemer,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    expect Some(_redemption_datum) = datum
    when redeemer is {
      RedeemWinner { output_index: _ } -> True
      BurnCompleteSet { output_index: _ } -> True
      ClaimTimeout { output_index: _ } -> True
      ClaimDraw { output_index: _ } -> True
      SweepResidual { output_index: _ } -> True
    }
  }

  mint(redeemer: MintAction, _policy_id: PolicyId, _self: Transaction) {
    when redeemer is {
      MintSet { market_id: _ } -> True
      BurnSet { market_id: _ } -> True
      BurnWinner { market_id: _ } -> True
    }
  }

  else(_) {
    fail
  }
}

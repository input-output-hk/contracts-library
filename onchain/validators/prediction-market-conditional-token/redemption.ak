use cardano/transaction.{OutputReference, Transaction}
use prediction_market_conditional_token/types.{
  RedemptionDatum, RedemptionRedeemer,
}

validator redemption {
  spend(
    _datum: Option<RedemptionDatum>,
    _redeemer: RedemptionRedeemer,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    True
  }

  else(_) {
    fail
  }
}

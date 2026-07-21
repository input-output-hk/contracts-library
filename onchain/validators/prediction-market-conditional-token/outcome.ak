use cardano/transaction.{OutputReference, Transaction}
use prediction_market_conditional_token/types.{OutcomeDatum, OutcomeRedeemer}

validator outcome {
  spend(
    _datum: Option<OutcomeDatum>,
    _redeemer: OutcomeRedeemer,
    _own_ref: OutputReference,
    _self: Transaction,
  ) {
    True
  }

  else(_) {
    fail
  }
}

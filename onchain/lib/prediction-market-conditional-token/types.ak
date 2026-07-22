use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type TokenInfo {
  asset: AssetClass,
  amount: Int,
}

pub type Winner {
  Yes
  No
  Draw
}

pub type OutcomeDatum {
  market_id: ByteArray,
  cutoff: Int,
  winner: Option<Winner>,
  outcome_credential: Credential,
  resolution_timeout: Int,
  claim_deadline: Int,
  collateral: TokenInfo,
}

pub type OutcomeRedeemer {
  Resolve { winner: Winner }
}

pub type BeaconMintAction {
  MintBeacon { market_id: ByteArray }
}

pub type RedemptionDatum {
  market_id: ByteArray,
  beacon_policy: PolicyId,
}

pub type RedemptionRedeemer {
  RedeemWinner { output_index: Int }
  BurnCompleteSet { output_index: Int }
  ClaimTimeout { output_index: Int }
  ClaimDraw { output_index: Int }
  SweepResidual { output_index: Int }
}

pub type MintAction {
  MintSet { market_id: ByteArray }
  BurnSet { market_id: ByteArray }
  BurnWinner { market_id: ByteArray }
}

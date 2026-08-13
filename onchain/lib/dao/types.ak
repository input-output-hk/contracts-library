//// On-chain state and actions for the DAO proposal contract.
//// See `docs/explorations/dao/exporation.md` §9.2.

use aiken/crypto.{ScriptHash}

/// Governance thresholds required at each stage of a proposal's lifecycle.
/// All quantities are in staked-token units.
pub type ProposalThresholds {
  create: Int,
  cosign: Int,
  accept: Int,
  vote: Int,
  execute: Int,
}

/// Phase durations (POSIX **milliseconds**) for a proposal's lifecycle.
pub type ProposalTimingConfig {
  draft_length: Int,
  voting_length: Int,
  tally_length: Int,
}

/// Lifecycle status of a proposal.
pub type ProposalStatus {
  Draft { cosigning_stake: Int }
  Voting
  Tally { votes: Pairs<Int, Int> }
}

/// Immutable proposal state, written once at creation. `thresholds`,
/// `timing_config`, `start_time` and `results` are locked on creation;
/// only `status` evolves.
pub type ProposalDatum {
  thresholds: ProposalThresholds,
  timing_config: ProposalTimingConfig,
  start_time: Int,
  status: ProposalStatus,
  results: Pairs<Int, ScriptHash>,
}

/// DAO configuration, stored as the settings contract's opaque `current` datum.
/// The proposal minting policy reads thresholds and timings from here.
pub type DaoSettings {
  thresholds: ProposalThresholds,
  timings: ProposalTimingConfig,
}

/// Redeemer for the proposal token minting policy.
pub type ProposalTokenRedeemer {
  CreateProposal
}

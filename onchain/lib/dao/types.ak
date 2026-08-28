//// On-chain state and actions for the DAO contracts (stake, proposal, vote).
//// See `docs/explorations/dao/exporation.md` §9.

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/assets.{AssetName}
use cardano/transaction.{OutputReference}
use dao/locks.{Lock}

/// Stake position state.
pub type StakePositionDatum {
  owner: Credential,
  delegatee: Option<Credential>,
  locks: List<Lock>,
}

/// Actions on a stake position UTxO.
pub type StakeRedeemer {
  Deposit
  DelegateTo { delegatee: Option<Credential> }
  Withdraw { amount: Int }
  ClosePosition
  CreateProposal
  CosignProposal { proposal_id: AssetName }
  VoteProposal { proposal_id: AssetName, voted_option: Int }
}

/// Redeemer for the stake position NFT minting policy.
pub type StakePositionTokenRedeemer {
  CreatePosition { owner_utxo: OutputReference, out_idx: Int }
  CloseStakePosition
}

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
  Tally { votes: List<Int> }
}

/// Immutable proposal state, written once at creation. `thresholds`,
/// `timing_config`, `start_time` and `results` are locked on creation;
/// only `status` evolves.
pub type ProposalDatum {
  thresholds: ProposalThresholds,
  timing_config: ProposalTimingConfig,
  start_time: Int,
  status: ProposalStatus,
  results: List<ScriptHash>,
}

/// DAO configuration, stored as the settings contract's opaque `current` datum.
/// Besides the governance parameters, it publishes the sibling script hashes so
/// the validators can resolve cross-references at runtime instead of via
/// (cyclic) compile-time parameters.
pub type DaoSettings {
  thresholds: ProposalThresholds,
  timings: ProposalTimingConfig,
  /// Hash of the stake position validator (also the stake NFT policy id).
  stake_validator: ScriptHash,
  /// Hash of the proposal validator (also the proposal NFT policy id).
  proposal_validator: ScriptHash,
  /// Hash of the vote validator (also the vote NFT policy id).
  vote_validator: ScriptHash,
}

/// Redeemer for the proposal token minting policy.
pub type ProposalTokenRedeemer {
  MintProposal { results: List<ScriptHash>, out_idx: Int }
  BurnProposal
}

/// Spent proposal UTxO actions.
pub type ProposalRedeemer {
  Cosign
  AcceptDraft
  RejectDraft
  EndVotingStage
  TallyVotes
  EndProposal
}

/// Vote artifact datum.
pub type VoteDatum {
  stake_owner: Credential,
  proposal: ByteArray,
  voted_option: Int,
  stake: Int,
}

/// Actions on a vote artifact UTxO.
pub type VoteRedeemer {
  TallyVote
  Cancel
}

/// Redeemer for the vote NFT minting policy.
pub type VoteTokenRedeemer {
  MintVote { out_idx: Int }
  BurnVotes
}

/// Redeemer a poll-effect script expects when executed as its winning-effect
/// withdrawal (withdraw-0). It declares the intent of whoever triggers the
/// effect: which poll closed and which option won. It is intent, not proof —
/// both the proposal validator (`EndProposal`) and the candidate's own
/// `am_i_the_winner` check that the declaration matches on-chain reality.
pub type PollEffectRedeemer {
  ExecuteWinner { proposal_id: AssetName, winner_option: Int }
}

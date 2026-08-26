/**
 * Off-chain mirror of the on-chain types in `onchain/lib/dao/types.ak`.
 */

import type { Credential, OutputRef } from "../common";

export type { Credential };

/** A stake position holds the DAO's staked token under an NFT. */
export interface StakePositionDatum {
  owner: Credential;
  delegatee: Credential | null;
  /** (proposalTokenName, unlockTimeMs, lockedStake) tuples. */
  locks: Array<[string, number, bigint]>;
}

/** Actions on a stake position UTxO. */
export type StakeRedeemer =
  | { kind: "Deposit" }
  | { kind: "DelegateTo"; delegatee: Credential | null }
  | { kind: "Withdraw"; amount: bigint }
  | { kind: "ClosePosition" }
  | { kind: "CreateProposal" }
  | { kind: "CosignProposal" }
  | { kind: "VoteProposal" };

/** Redeemer for the stake position NFT minting policy. */
export type StakePositionTokenRedeemer =
  | { kind: "CreatePosition" }
  | { kind: "CloseStakePosition" };

/** Governance thresholds required at each stage of a proposal's lifecycle. */
export interface ProposalThresholds {
  create: bigint;
  cosign: bigint;
  accept: bigint;
  vote: bigint;
  execute: bigint;
}

/** Phase durations (POSIX milliseconds) for a proposal's lifecycle. */
export interface ProposalTimingConfig {
  draftLength: number;
  votingLength: number;
  tallyLength: number;
}

/** Lifecycle status of a proposal. */
export type ProposalStatus =
  | { kind: "Draft"; cosigningStake: bigint }
  | { kind: "Voting" }
  | { kind: "Tally"; votes: Map<number, bigint> };

/** Immutable proposal state, written once at creation. */
export interface ProposalDatum {
  thresholds: ProposalThresholds;
  timingConfig: ProposalTimingConfig;
  startTime: number;
  status: ProposalStatus;
  /** resultId -> script hash to execute. */
  results: Map<number, string>;
}

/**
 * DAO configuration, stored as the settings contract's opaque `current` datum.
 * Publishes thresholds/timings plus the sibling validator hashes so the
 * validators can resolve cross-references at runtime.
 */
export interface DaoSettings {
  thresholds: ProposalThresholds;
  timings: ProposalTimingConfig;
  /** Hash of the stake validator (also the stake NFT policy id). */
  stakeValidator: string;
  /** Hash of the proposal validator (also the proposal NFT policy id). */
  proposalValidator: string;
  /** Hash of the vote validator (also the vote NFT policy id). */
  voteValidator: string;
}

/** Redeemer for the proposal token minting policy. */
export type ProposalTokenRedeemer =
  | { kind: "MintProposal" }
  | { kind: "BurnProposal" };

/** Spent proposal UTxO actions. */
export type ProposalRedeemer =
  | { kind: "Cosign" }
  | { kind: "AcceptDraft" }
  | { kind: "RejectDraft" }
  | { kind: "EndVotingStage" }
  | { kind: "TallyVotes" }
  | { kind: "EndProposal" };

/** Vote artifact datum. */
export interface VoteDatum {
  stakeOwner: AddressData;
  proposal: string;
  votedOption: number;
  stake: bigint;
}

/** Off-chain mirror of `cardano/address/Address`. */
export interface AddressData {
  paymentCredential: Credential;
  stakeCredential: Credential | null;
}

/** Actions on a vote artifact UTxO. */
export type VoteRedeemer = { kind: "TallyVote" };

/** Redeemer for the vote NFT minting policy. */
export type VoteTokenRedeemer = { kind: "MintVote" } | { kind: "BurnVotes" };

/** Parameters of the `proposal` validator (blueprint order). */
export interface ProposalParams {
  settingsUtxo: OutputRef;
  stakeNftPolicy: string;
  stakeNftName: string;
  stakeTokenPolicy: string;
  stakeTokenName: string;
}

/** Parameters of the `stake` validator (blueprint order). */
export interface StakeParams {
  stakeTokenPolicy: string;
  stakeTokenName: string;
  settingsUtxo: OutputRef;
}

/** Parameters of the `vote` validator (blueprint order). */
export interface VoteParams {
  stakeNftPolicy: string;
  stakeTokenPolicy: string;
  stakeTokenName: string;
  proposalPolicy: string;
}

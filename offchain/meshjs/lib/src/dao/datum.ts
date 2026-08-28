/**
 * Datum/redeemer encoding for the DAO contracts.
 *
 * CBOR constructor layout matching the Aiken blueprint in onchain/plutus.json:
 *   StakePositionDatum  = Constr 0 [owner: Credential, delegatee: Option<Credential>, locks: [Tuple3]]
 *   StakeRedeemer       = Deposit=0 | DelegateTo{delegatee}=1 | Withdraw{amount}=2
 *                       | ClosePosition=3 | CreateProposal=4 | CosignProposal{proposal_id}=5
 *                       | VoteProposal{proposal_id, voted_option}=6
 *   StakePositionTokenRedeemer = CreatePosition{owner_utxo, out_idx}=0 | CloseStakePosition=1
 *   ProposalThresholds  = Constr 0 [create, cosign, accept, vote, execute]
 *   ProposalTimingConfig= Constr 0 [draft_length, voting_length, tally_length]
 *   ProposalStatus      = Draft{cosigning_stake}=0 | Voting=1 | Tally{votes: [Int]}=2
 *   ProposalDatum       = Constr 0 [thresholds, timing_config, start_time, status, results: [ScriptHash]]
 *   DaoSettings         = Constr 0 [thresholds, timings, stake, proposal, vote validator]
 *   ProposalTokenRedeemer = MintProposal{results, out_idx}=0 | BurnProposal=1
 *   ProposalRedeemer    = Cosign=0 | AcceptDraft=1 | RejectDraft=2 | EndVotingStage=3
 *                       | TallyVotes=4 | EndProposal=5
 *   VoteDatum           = Constr 0 [stake_owner: Credential, proposal, voted_option, stake]
 *   VoteRedeemer        = TallyVote=0 | Cancel=1
 *   VoteTokenRedeemer   = MintVote{out_idx}=0 | BurnVotes=1
 *   PollEffectRedeemer  = ExecuteWinner{proposal_id, winner_option}=0
 */

import {
  mConStr,
  mConStr0,
  mConStr1,
  mConStr2,
  type Data,
  type TxInput,
} from "@meshsdk/core";

import { credentialToData } from "../common";
import { outputRefToData } from "../settings/datum";
import type {
  DaoSettings,
  PollEffectParams,
  PollEffectRedeemer,
  ProposalDatum,
  ProposalParams,
  ProposalRedeemer,
  ProposalStatus,
  ProposalThresholds,
  ProposalTimingConfig,
  ProposalTokenRedeemer,
  StakeParams,
  StakePositionDatum,
  StakePositionTokenRedeemer,
  StakeRedeemer,
  VoteDatum,
  VoteParams,
  VoteRedeemer,
  VoteTokenRedeemer,
} from "./types";

export { credentialToData, outputRefToData };

function option<T>(value: T | null, wrap: (v: T) => Data): Data {
  return value === null ? mConStr1([]) : mConStr0([wrap(value)]);
}

// ------------------------------------------------------------ stake datum

export function stakePositionDatumToData(d: StakePositionDatum): Data {
  return mConStr0([
    credentialToData(d.owner),
    option(d.delegatee, (c) => credentialToData(c)),
    d.locks.map(([name, unlock, amount]) => [name, unlock, amount]),
  ]);
}

// ------------------------------------------------------------ stake redeemers

export function stakeRedeemerToData(r: StakeRedeemer): Data {
  switch (r.kind) {
    case "Deposit":
      return mConStr0([]);
    case "DelegateTo":
      return mConStr1([option(r.delegatee, (c) => credentialToData(c))]);
    case "Withdraw":
      return mConStr2([r.amount]);
    case "ClosePosition":
      return mConStr(3, []);
    case "CreateProposal":
      return mConStr(4, []);
    case "CosignProposal":
      return mConStr(5, [r.proposalId]);
    case "VoteProposal":
      return mConStr(6, [r.proposalId, r.votedOption]);
  }
}

export function createPositionRedeemer(
  ownerUtxo: TxInput,
  outIdx: number,
): Data {
  return mConStr0([outputRefToData(ownerUtxo), outIdx]);
}

export function closeStakePositionRedeemer(): Data {
  return mConStr1([]);
}

export function stakePositionTokenRedeemerToData(
  r: StakePositionTokenRedeemer,
): Data {
  return r.kind === "CreatePosition"
    ? createPositionRedeemer(r.ownerUtxo, r.outIdx)
    : closeStakePositionRedeemer();
}

// ------------------------------------------------------------ proposal datum

export function proposalThresholdsToData(t: ProposalThresholds): Data {
  return mConStr0([t.create, t.cosign, t.accept, t.vote, t.execute]);
}

export function proposalTimingConfigToData(t: ProposalTimingConfig): Data {
  return mConStr0([t.draftLength, t.votingLength, t.tallyLength]);
}

export function proposalStatusToData(s: ProposalStatus): Data {
  switch (s.kind) {
    case "Draft":
      return mConStr0([s.cosigningStake]);
    case "Voting":
      return mConStr1([]);
    case "Tally":
      return mConStr2([s.votes]);
  }
}

export function proposalDatumToData(d: ProposalDatum): Data {
  return mConStr0([
    proposalThresholdsToData(d.thresholds),
    proposalTimingConfigToData(d.timingConfig),
    d.startTime,
    proposalStatusToData(d.status),
    d.results,
  ]);
}

export function daoSettingsToData(s: DaoSettings): Data {
  return mConStr0([
    proposalThresholdsToData(s.thresholds),
    proposalTimingConfigToData(s.timings),
    s.stakeValidator,
    s.proposalValidator,
    s.voteValidator,
  ]);
}

// ------------------------------------------------------------ proposal redeemers

export function proposalTokenRedeemerToData(r: ProposalTokenRedeemer): Data {
  return r.kind === "MintProposal"
    ? mintProposalRedeemer(r.results, r.outIdx)
    : mConStr1([]);
}

export function mintProposalRedeemer(results: string[], outIdx: number): Data {
  return mConStr0([results, outIdx]);
}

export function burnProposalRedeemer(): Data {
  return mConStr1([]);
}

export function proposalRedeemerToData(r: ProposalRedeemer): Data {
  switch (r.kind) {
    case "Cosign":
      return mConStr0([]);
    case "AcceptDraft":
      return mConStr1([]);
    case "RejectDraft":
      return mConStr2([]);
    case "EndVotingStage":
      return mConStr(3, []);
    case "TallyVotes":
      return mConStr(4, []);
    case "EndProposal":
      return mConStr(5, []);
  }
}

export function cosignRedeemer(): Data {
  return proposalRedeemerToData({ kind: "Cosign" });
}

export function acceptDraftRedeemer(): Data {
  return proposalRedeemerToData({ kind: "AcceptDraft" });
}

export function rejectDraftRedeemer(): Data {
  return proposalRedeemerToData({ kind: "RejectDraft" });
}

export function endVotingStageRedeemer(): Data {
  return proposalRedeemerToData({ kind: "EndVotingStage" });
}

export function tallyVotesRedeemer(): Data {
  return proposalRedeemerToData({ kind: "TallyVotes" });
}

export function endProposalRedeemer(): Data {
  return proposalRedeemerToData({ kind: "EndProposal" });
}

// ------------------------------------------------------------ vote datum

export function voteDatumToData(d: VoteDatum): Data {
  return mConStr0([
    credentialToData(d.stakeOwner),
    d.proposal,
    d.votedOption,
    d.stake,
  ]);
}

export function tallyVoteRedeemer(): Data {
  return mConStr0([]);
}

export function cancelVoteRedeemer(): Data {
  return mConStr1([]);
}

export function voteRedeemerToData(r: VoteRedeemer): Data {
  return r.kind === "TallyVote" ? tallyVoteRedeemer() : cancelVoteRedeemer();
}

export function voteTokenRedeemerToData(r: VoteTokenRedeemer): Data {
  return r.kind === "MintVote" ? mintVoteRedeemer(r.outIdx) : mConStr1([]);
}

export function mintVoteRedeemer(outIdx: number): Data {
  return mConStr0([outIdx]);
}

export function burnVotesRedeemer(): Data {
  return mConStr1([]);
}

// ------------------------------------------------------------ validator params

export function proposalParamsToData(p: ProposalParams): Data[] {
  return [
    p.stakeTokenPolicy,
    p.stakeTokenName,
    p.settingsPolicy,
    p.settingsTokenName,
  ];
}

export function stakeParamsToData(p: StakeParams): Data[] {
  return [
    p.stakeTokenPolicy,
    p.stakeTokenName,
    p.settingsPolicy,
    p.settingsTokenName,
  ];
}

export function voteParamsToData(p: VoteParams): Data[] {
  return [
    p.stakeTokenPolicy,
    p.stakeTokenName,
    p.settingsPolicy,
    p.settingsTokenName,
  ];
}

// --------------------------------------------------------- poll-effect candidate

export function pollEffectParamsToData(p: PollEffectParams): Data[] {
  return [p.proposalPolicy];
}

export function pollEffectRedeemerToData(r: PollEffectRedeemer): Data {
  switch (r.kind) {
    case "ExecuteWinner":
      return mConStr0([r.proposalId, r.winnerOption]);
  }
}

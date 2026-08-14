use cardano/address.{from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
  placeholder,
}
use dao/types.{
  Cosign, ProposalDatum, ProposalStatus, ProposalThresholds,
  ProposalTimingConfig, TallyVote, TallyVotes, VoteDatum, VoteProposal,
}
use dao/vote/mint.{validate_burn_votes, validate_mint_vote}
use dao/vote/spend.{validate_vote_spend}

// ------------------------------------------------------------------- fixtures

const vote_policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const proposal_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const stake_hash = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const gov_policy = #"22222222222222222222222222222222222222222222222222222222"

const gov_name = "GOV"

const voter_hash = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const prop_nft = "PROP"

const stake_nft = "S"

const vote_nft = "V"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn proposal_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 5 }
}

fn proposal_utxo(status: ProposalStatus) -> Input {
  Input {
    output_reference: proposal_ref(),
    output: Output {
      address: from_script(proposal_policy),
      value: assets.from_asset(proposal_policy, prop_nft, 1),
      datum: InlineDatum(
        ProposalDatum {
          thresholds: ProposalThresholds {
            create: 100,
            cosign: 50,
            accept: 100,
            vote: 10,
            execute: 200,
          },
          timing_config: ProposalTimingConfig {
            draft_length: 1000,
            voting_length: 2000,
            tally_length: 3000,
          },
          start_time: 500,
          status,
          results: [],
        },
      ),
      reference_script: None,
    },
  }
}

fn stake_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 1 }
}

fn stake_input(s: Int) -> Input {
  Input {
    output_reference: stake_ref(),
    output: Output {
      address: from_script(stake_hash),
      value: assets.from_asset(stake_hash, stake_nft, 1)
        |> assets.add(gov_policy, gov_name, s),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn vote_output(proposal: ByteArray, s: Int) -> Output {
  Output {
    address: from_script(vote_policy),
    value: assets.from_asset(vote_policy, vote_nft, 1),
    datum: InlineDatum(
      VoteDatum {
        stake_owner: from_script(voter_hash),
        proposal,
        voted_option: 1,
        stake: s,
      },
    ),
    reference_script: None,
  }
}

// --------------------------------------------------------------- spend a vote

test vote_spend_ok() {
  let d =
    VoteDatum {
      stake_owner: from_script(voter_hash),
      proposal: prop_nft,
      voted_option: 1,
      stake: 5,
    }
  let tally_r: Data = TallyVotes
  let proposal_in = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let tx =
    Transaction {
      ..placeholder,
      inputs: [proposal_in],
      redeemers: [Pair(Spend(proposal_ref()), tally_r)],
    }
  validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

test rejects_vote_spend_without_tally() {
  let d =
    VoteDatum {
      stake_owner: from_script(voter_hash),
      proposal: prop_nft,
      voted_option: 1,
      stake: 5,
    }
  // proposal is spent with a non-tally redeemer
  let other_r: Data = Cosign
  let proposal_in = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let tx =
    Transaction {
      ..placeholder,
      inputs: [proposal_in],
      redeemers: [Pair(Spend(proposal_ref()), other_r)],
    }
  !validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

// ----------------------------------------------------------------- mint votes

test mint_vote_ok() {
  let vote_r: Data = VoteProposal
  let tx =
    Transaction {
      ..placeholder,
      inputs: [stake_input(5)],
      reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
      outputs: [vote_output(prop_nft, 5)],
      mint: assets.from_asset(vote_policy, vote_nft, 1),
      redeemers: [Pair(Spend(stake_ref()), vote_r)],
    }
  validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    tx,
  )
}

test rejects_mint_vote_wrong_stake_record() {
  let vote_r: Data = VoteProposal
  // the vote artifact records 7 but the stake only holds 5
  let tx =
    Transaction {
      ..placeholder,
      inputs: [stake_input(5)],
      reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
      outputs: [vote_output(prop_nft, 7)],
      mint: assets.from_asset(vote_policy, vote_nft, 1),
      redeemers: [Pair(Spend(stake_ref()), vote_r)],
    }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    tx,
  )
}

test rejects_mint_vote_when_not_voting() {
  let vote_r: Data = VoteProposal
  let tx =
    Transaction {
      ..placeholder,
      inputs: [stake_input(5)],
      reference_inputs: [
        proposal_utxo(ProposalStatus.Draft { cosigning_stake: 0 }),
      ],
      outputs: [vote_output(prop_nft, 5)],
      mint: assets.from_asset(vote_policy, vote_nft, 1),
      redeemers: [Pair(Spend(stake_ref()), vote_r)],
    }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    tx,
  )
}

// ----------------------------------------------------------------- burn votes

test burn_votes_ok() {
  let tx =
    Transaction {
      ..placeholder,
      mint: assets.from_asset(vote_policy, vote_nft, -1),
    }
  validate_burn_votes(vote_policy, tx)
}

test rejects_burn_votes_empty() {
  validate_burn_votes(vote_policy, placeholder) == False
}

test rejects_burn_votes_positive() {
  let tx =
    Transaction {
      ..placeholder,
      mint: assets.from_asset(vote_policy, vote_nft, 1),
    }
  !validate_burn_votes(vote_policy, tx)
}

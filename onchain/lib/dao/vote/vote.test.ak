use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
  placeholder,
}
use dao/types.{
  Cosign, ProposalDatum, ProposalStatus, ProposalThresholds,
  ProposalTimingConfig, StakePositionDatum, TallyVote, TallyVotes, VoteDatum,
  VoteProposal,
}
use dao/utils.{nft_name_from_ref}
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
          results: [voter_hash, voter_hash],
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
      datum: InlineDatum(
        StakePositionDatum {
          owner: Script(voter_hash),
          delegatee: None,
          locks: [],
        },
      ),
      reference_script: None,
    },
  }
}

fn vote_ref() -> OutputReference {
  stake_ref()
}

/// The vote NFT name: the hash of the spent stake UTxO's output reference, as
/// enforced by the vote mint.
fn vote_name() -> ByteArray {
  nft_name_from_ref(stake_ref())
}

fn vote_output(proposal: ByteArray, s: Int) -> Output {
  Output {
    address: from_script(vote_policy),
    value: assets.from_asset(vote_policy, vote_name(), 1),
    datum: InlineDatum(
      VoteDatum {
        stake_owner: Script(voter_hash),
        proposal,
        voted_option: 1,
        stake: s,
      },
    ),
    reference_script: None,
  }
}

fn vote_datum() -> VoteDatum {
  VoteDatum {
    stake_owner: Script(voter_hash),
    proposal: prop_nft,
    voted_option: 1,
    stake: 5,
  }
}

fn vote_utxo(d: VoteDatum) -> Input {
  Input {
    output_reference: vote_ref(),
    output: Output {
      address: from_script(vote_policy),
      value: assets.from_asset(vote_policy, vote_name(), 1),
      datum: InlineDatum(d),
      reference_script: None,
    },
  }
}

// --------------------------------------------------------------- spend a vote

test vote_spend_ok() {
  let d = vote_datum()
  let tally_r: Data = TallyVotes
  let proposal_in = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let tx = Transaction {
    ..placeholder,
    inputs: [proposal_in, vote_utxo(d)],
    redeemers: [Pair(Spend(proposal_ref()), tally_r)],
  }
  validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

test rejects_vote_spend_without_tally() {
  let d = vote_datum()
  // proposal is spent with a non-tally redeemer
  let other_r: Data = Cosign
  let proposal_in = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let tx = Transaction {
    ..placeholder,
    inputs: [proposal_in, vote_utxo(d)],
    redeemers: [Pair(Spend(proposal_ref()), other_r)],
  }
  !validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

test rejects_vote_spend_transferring_nft() {
  // the vote NFT is carried into an output instead of being burned
  let d = vote_datum()
  let tally_r: Data = TallyVotes
  let proposal_in = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let transfer = Output {
    address: from_script(voter_hash),
    value: assets.from_asset(vote_policy, vote_name(), 1),
    datum: NoDatum,
    reference_script: None,
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [proposal_in, vote_utxo(d)],
    outputs: [transfer],
    redeemers: [Pair(Spend(proposal_ref()), tally_r)],
  }
  !validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

test rejects_vote_spend_wrong_proposal_address() {
  // the tallying proposal input must sit at the proposal address
  let d = vote_datum()
  let tally_r: Data = TallyVotes
  let voting = proposal_utxo(ProposalStatus.Tally { votes: [] })
  let bad_proposal = Input {
    ..voting,
    output: Output { ..voting.output, address: from_script(stake_hash) },
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [bad_proposal, vote_utxo(d)],
    redeemers: [Pair(Spend(proposal_ref()), tally_r)],
  }
  !validate_vote_spend(proposal_policy, d, TallyVote, stake_ref(), tx)
}

// ----------------------------------------------------------------- mint votes

test mint_vote_ok() {
  let vote_r: Data = VoteProposal { voted_option: 1 }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [vote_output(prop_nft, 5)],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_wrong_token_name() {
  // the vote NFT name must be the hash of the spent stake UTxO's reference
  let vote_r: Data = VoteProposal { voted_option: 1 }
  let out = Output {
    ..vote_output(prop_nft, 5),
    value: assets.from_asset(vote_policy, vote_nft, 1),
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [out],
    mint: assets.from_asset(vote_policy, vote_nft, 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_extra_token_output() {
  // the vote UTxO may hold nothing but its NFT (and lovelace)
  let vote_r: Data = VoteProposal { voted_option: 1 }
  let out = Output {
    ..vote_output(prop_nft, 5),
    value: assets.from_asset(vote_policy, vote_name(), 1)
      |> assets.add(gov_policy, gov_name, 5),
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [out],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_wrong_stake_record() {
  let vote_r: Data = VoteProposal { voted_option: 1 }
  // the vote artifact records 7 but the stake only holds 5
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [vote_output(prop_nft, 7)],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_when_not_voting() {
  let vote_r: Data = VoteProposal { voted_option: 1 }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [
      proposal_utxo(ProposalStatus.Draft { cosigning_stake: 0 }),
    ],
    outputs: [vote_output(prop_nft, 5)],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_option_out_of_range() {
  let vote_r: Data = VoteProposal { voted_option: 2 }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [vote_output(prop_nft, 5)],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

test rejects_mint_vote_reference_script_output() {
  let vote_r: Data = VoteProposal { voted_option: 1 }
  let bad_output = Output {
    ..vote_output(prop_nft, 5),
    reference_script: Some(vote_policy),
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [stake_input(5)],
    reference_inputs: [proposal_utxo(ProposalStatus.Voting)],
    outputs: [bad_output],
    mint: assets.from_asset(vote_policy, vote_name(), 1),
    redeemers: [Pair(Spend(stake_ref()), vote_r)],
  }
  !validate_mint_vote(
    stake_hash,
    gov_policy,
    gov_name,
    proposal_policy,
    vote_policy,
    0,
    tx,
  )
}

// ----------------------------------------------------------------- burn votes

test burn_votes_ok() {
  let tx = Transaction {
    ..placeholder,
    mint: assets.from_asset(vote_policy, vote_nft, -1),
  }
  validate_burn_votes(vote_policy, tx)
}

test rejects_burn_votes_empty() {
  validate_burn_votes(vote_policy, placeholder) == False
}

test rejects_burn_votes_positive() {
  let tx = Transaction {
    ..placeholder,
    mint: assets.from_asset(vote_policy, vote_nft, 1),
  }
  !validate_burn_votes(vote_policy, tx)
}

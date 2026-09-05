use aiken/collection/list
use aiken/interval.{Finite}
use authorization.{is_authorized}
use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName, PolicyId, Value, has_nft, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, resolve_input,
}
use dao/locks.{Lock, free_stake, has_proposal, prune_expired}
use dao/types.{DaoSettings, ProposalDatum, ProposalStatus, StakePositionDatum}
use dao/utils.{
  find_continuation_output, nft_name_from_ref, proposal_token_name,
  single_nft_name,
}

/// Spending logic for a stake position UTxO.
///
/// The stake validator's own hash doubles as the stake NFT policy id, so the
/// position UTxO holds one NFT under `own_hash`. Governance actions
/// (`CreateProposal`, `CosignProposal`, `VoteProposal`) record locks that
/// freeze the committed stake until the relevant proposal phase ends; the
/// governance parameters (`settings`) are resolved from the settings UTxO by
/// the validator wrapper, which dispatches the redeemer to the matching
/// function below.
/// Resolve the stake position's identity: its address, value, policy id, NFT
/// name, and staked-token balance.
fn position(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> (Address, Value, PolicyId, AssetName, Int) {
  let Transaction { inputs, .. } = self
  let own_input = resolve_input(inputs, own_ref)
  let Output { address: own_addr, value: own_value, .. } = own_input
  expect Script(own_hash) = own_addr.payment_credential
  let nft = single_nft_name(own_value, own_hash)
  let in_stake = quantity_of(own_value, staked_token_policy, staked_token_name)
  (own_addr, own_value, own_hash, nft, in_stake)
}

pub fn validate_stake_deposit(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, _, own_hash, nft, in_stake) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let  
      Transaction {
        outputs,
        extra_signatories,
        withdrawals,
        validity_range,
        ..
      }
    = self
  expect Finite(now) = validity_range.lower_bound.bound_type
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    is_authorized(datum.owner, extra_signatories, withdrawals),
    cont.owner == datum.owner,
    cont.delegatee == datum.delegatee,
    cont.locks == prune_expired(datum.locks, now),
    quantity_of(out.value, staked_token_policy, staked_token_name) >= in_stake,
    quantity_of(out.value, own_hash, nft) == 1,
    list.length(assets.flatten(out.value)) == 3,
  }
}

pub fn validate_stake_delegate(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  delegatee: Option<Credential>,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, own_value, _, _, _) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let Transaction { outputs, extra_signatories, withdrawals, .. } = self
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    is_authorized(datum.owner, extra_signatories, withdrawals),
    cont.owner == datum.owner,
    cont.delegatee == delegatee,
    cont.locks == datum.locks,
    assets.match(out.value, own_value, >=),
  }
}

pub fn validate_stake_withdraw(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  amount: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, _, own_hash, nft, in_stake) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let  
      Transaction {
        outputs,
        extra_signatories,
        withdrawals,
        validity_range,
        ..
      }
    = self
  expect Finite(now) = validity_range.lower_bound.bound_type
  let pruned = prune_expired(datum.locks, now)
  let free = free_stake(in_stake, pruned)
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    amount >= 0,
    amount <= free,
    is_authorized(datum.owner, extra_signatories, withdrawals),
    cont.owner == datum.owner,
    cont.delegatee == datum.delegatee,
    cont.locks == pruned,
    quantity_of(out.value, staked_token_policy, staked_token_name) == in_stake - amount,
    quantity_of(out.value, own_hash, nft) == 1,
    list.length(assets.flatten(out.value)) == 3,
  }
}

pub fn validate_stake_close_position(
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (_, _, own_hash, nft, _) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let Transaction { mint, extra_signatories, withdrawals, validity_range, .. } = self
  expect Finite(now) = validity_range.lower_bound.bound_type
  let all_locks_expired = prune_expired(datum.locks, now) == []
  let must_burn_stake_nft = quantity_of(mint, own_hash, nft) == -1
  and {
    all_locks_expired,
    must_burn_stake_nft,
    is_authorized(datum.owner, extra_signatories, withdrawals),
  }
}

pub fn validate_stake_create_proposal(
  settings: DaoSettings,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, own_value, _, _, in_stake) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let  
      Transaction {
        outputs,
        mint,
        extra_signatories,
        withdrawals,
        validity_range,
        ..
      }
    = self
  expect Finite(now) = validity_range.lower_bound.bound_type
  let p_id = proposal_token_name(own_ref)
  let new_lock = Lock {
    proposal_id: p_id,
    unlock_time: now + settings.timings.draft_length,
    stake: in_stake,
  }
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    is_authorized(datum.owner, extra_signatories, withdrawals),
    in_stake >= settings.thresholds.create,
    quantity_of(mint, settings.proposal_validator, p_id) == 1,
    cont.owner == datum.owner,
    cont.delegatee == datum.delegatee,
    cont.locks == list.push(datum.locks, new_lock),
    assets.match(out.value, own_value, >=),
  }
}

pub fn validate_stake_cosign(
  settings: DaoSettings,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  proposal_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, own_value, _, _, in_stake) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let Transaction { inputs, outputs, extra_signatories, withdrawals, .. } = self
  let proposal = proposal_datum(
    inputs,
    settings.proposal_validator,
    proposal_id,
  )
  let new_lock = Lock {
    proposal_id,
    unlock_time: proposal.start_time + proposal.timing_config.draft_length,
    stake: in_stake,
  }
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    is_authorized(vote_auth(datum), extra_signatories, withdrawals),
    is_draft(proposal.status),
    in_stake >= proposal.thresholds.cosign,
    !has_proposal(datum.locks, proposal_id),
    cont.owner == datum.owner,
    cont.delegatee == datum.delegatee,
    cont.locks == list.concat(datum.locks, [new_lock]),
    assets.match(out.value, own_value, >=),
  }
}

pub fn validate_stake_vote(
  settings: DaoSettings,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  proposal_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let (own_addr, own_value, _, _, in_stake) = position(
    staked_token_policy,
    staked_token_name,
    own_ref,
    self,
  )
  let  
      Transaction {
        reference_inputs,
        outputs,
        mint,
        extra_signatories,
        withdrawals,
        validity_range,
        ..
      }
    = self
  expect Finite(now) = validity_range.lower_bound.bound_type
  expect Finite(upper) = validity_range.upper_bound.bound_type
  let proposal = proposal_datum(
    reference_inputs,
    settings.proposal_validator,
    proposal_id,
  )
  let unlock = proposal.start_time + proposal.timing_config.draft_length + proposal.timing_config.voting_length
  let new_lock = Lock { proposal_id, unlock_time: unlock, stake: in_stake }
  let out = find_continuation_output(outputs, own_addr)
  let cont = out_datum(out)
  and {
    is_authorized(vote_auth(datum), extra_signatories, withdrawals),
    proposal.status == ProposalStatus.Voting,
    in_stake >= proposal.thresholds.vote,
    !has_proposal(datum.locks, proposal_id),
    upper <= unlock,
    cont.owner == datum.owner,
    cont.delegatee == datum.delegatee,
    cont.locks == prune_expired(list.concat(datum.locks, [new_lock]), now),
    assets.match(out.value, own_value, >=),
    quantity_of(mint, settings.vote_validator, nft_name_from_ref(own_ref)) == 1,
  }
}

/// The credential authorized to co-sign/vote: the delegatee if set, else the owner.
fn vote_auth(datum: StakePositionDatum) -> Credential {
  when datum.delegatee is {
    Some(d) -> d
    None -> datum.owner
  }
}

fn is_draft(status: ProposalStatus) -> Bool {
  when status is {
    ProposalStatus.Draft { .. } -> True
    _ -> False
  }
}

fn out_datum(out: Output) -> StakePositionDatum {
  expect InlineDatum(d) = out.datum
  expect sd: StakePositionDatum = d
  sd
}

fn proposal_datum(
  inputs: List<Input>,
  policy: PolicyId,
  proposal_id: AssetName,
) -> ProposalDatum {
  let input = list.expect_find(
    inputs,
    fn(input) { has_nft(input.output.value, policy, proposal_id) },
  )
  expect InlineDatum(d) = input.output.datum
  expect pd: ProposalDatum = d
  pd
}

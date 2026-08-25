use aiken/collection/list
use aiken/interval.{Finite}
use authorization.{is_authorized}
use cardano/address.{Address, Credential, Script}
use cardano/assets.{AssetName, PolicyId, has_any_nft, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, resolve_input,
}
use dao/locks.{free_stake, has_proposal, prune_expired}
use dao/types.{
  ClosePosition, CosignProposal, CreateProposal, DaoSettings, DelegateTo,
  Deposit, ProposalDatum, ProposalStatus, StakePositionDatum, StakeRedeemer,
  VoteProposal, Withdraw,
}
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
/// the validator wrapper before this function is called.
pub fn validate_stake_spend(
  settings: DaoSettings,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: StakePositionDatum,
  redeemer: StakeRedeemer,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let  
      Transaction {
        inputs,
        reference_inputs,
        outputs,
        mint,
        extra_signatories,
        withdrawals,
        validity_range,
        ..
      }
    = self

  let own_input = resolve_input(inputs, own_ref)
  let Output { address: own_addr, value: own_value, .. } = own_input

  expect Script(own_hash) = own_addr.payment_credential
  let nft = single_nft_name(own_value, own_hash)
  let in_stake = quantity_of(own_value, staked_token_policy, staked_token_name)

  when redeemer is {
    Deposit -> {
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
    DelegateTo { delegatee } -> {
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
    Withdraw { amount } -> {
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
    ClosePosition -> {
      expect Finite(now) = validity_range.lower_bound.bound_type
      let all_locks_expired = prune_expired(datum.locks, now) == []
      let must_burn_stake_nft = quantity_of(mint, own_hash, nft) == -1
      and {
        all_locks_expired,
        must_burn_stake_nft,
        is_authorized(datum.owner, extra_signatories, withdrawals),
      }
    }
    CreateProposal -> {
      expect Finite(now) = validity_range.lower_bound.bound_type
      let p_id = proposal_token_name(own_ref)
      let new_lock = (p_id, now + settings.timings.draft_length, in_stake)
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
    CosignProposal -> {
      let (p_id, proposal) = proposal_with_nft(
        inputs,
        settings.proposal_validator,
      )
      let new_lock = (
        p_id,
        proposal.start_time + proposal.timing_config.draft_length,
        in_stake,
      )
      let out = find_continuation_output(outputs, own_addr)
      let cont = out_datum(out)
      and {
        is_authorized(vote_auth(datum), extra_signatories, withdrawals),
        is_draft(proposal.status),
        in_stake >= proposal.thresholds.cosign,
        !has_proposal(datum.locks, p_id),
        cont.owner == datum.owner,
        cont.delegatee == datum.delegatee,
        cont.locks == list.concat(datum.locks, [new_lock]),
        assets.match(out.value, own_value, >=),
      }
    }
    VoteProposal { voted_option: _option } -> {
      expect Finite(now) = validity_range.lower_bound.bound_type
      expect Finite(upper) = validity_range.upper_bound.bound_type
      let (p_id, proposal) = proposal_with_nft(
        reference_inputs,
        settings.proposal_validator,
      )
      let unlock = proposal.start_time + proposal.timing_config.draft_length + proposal.timing_config.voting_length
      let new_lock = (p_id, unlock, in_stake)
      let out = find_continuation_output(outputs, own_addr)
      let cont = out_datum(out)
      and {
        is_authorized(vote_auth(datum), extra_signatories, withdrawals),
        proposal.status == ProposalStatus.Voting,
        in_stake >= proposal.thresholds.vote,
        !has_proposal(datum.locks, p_id),
        upper <= unlock,
        cont.owner == datum.owner,
        cont.delegatee == datum.delegatee,
        cont.locks == prune_expired(list.concat(datum.locks, [new_lock]), now),
        assets.match(out.value, own_value, >=),
        quantity_of(mint, settings.vote_validator, nft_name_from_ref(own_ref)) == 1,
      }
    }
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

fn proposal_with_nft(
  inputs: List<Input>,
  policy: PolicyId,
) -> (AssetName, ProposalDatum) {
  let input = list.expect_find(
    inputs,
    fn(input) { has_any_nft(input.output.value, policy) },
  )
  let name = single_nft_name(input.output.value, policy)
  expect InlineDatum(d) = input.output.datum
  expect pd: ProposalDatum = d
  (name, pd)
}

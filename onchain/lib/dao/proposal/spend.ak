use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/interval.{Finite}
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, lovelace_of, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use dao/types.{
  AcceptDraft, Cosign, CosignProposal, EndProposal, EndVotingStage,
  ProposalDatum, ProposalRedeemer, ProposalStatus, RejectDraft, StakeRedeemer,
  TallyVotes, VoteDatum,
}
use dao/utils.{find_input_by_policy, single_nft_name, spend_redeemer}

/// Spending logic for a proposal UTxO. The proposal validator's own hash is the
/// proposal NFT policy id, so the UTxO carries one NFT under `own_hash`.
pub fn validate_proposal_spend(
  vote_policy: PolicyId,
  stake_nft_policy: PolicyId,
  stake_token_policy: PolicyId,
  stake_token_name: AssetName,
  datum: ProposalDatum,
  redeemer: ProposalRedeemer,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = self

  expect Some(own_input) = find_input(inputs, own_ref)
  let own_addr = own_input.output.address
  expect Script(own_hash) = own_addr.payment_credential
  let p_id = single_nft_name(own_input.output.value, own_hash)

  when redeemer is {
    Cosign -> {
      expect ProposalStatus.Draft { cosigning_stake: n } = datum.status
      let cont = continuation(outputs, own_addr, own_hash, p_id)
      let stake_input = find_input_by_policy(inputs, stake_nft_policy)
      let s =
        quantity_of(
          stake_input.output.value,
          stake_token_policy,
          stake_token_name,
        )
      let cosigning = {
        expect action: StakeRedeemer =
          spend_redeemer(self, stake_input.output_reference)
        action == CosignProposal
      }
      and {
        cosigning,
        cont.status == ProposalStatus.Draft { cosigning_stake: n + s },
        immutables_ok(cont, datum),
      }
    }
    AcceptDraft -> {
      expect ProposalStatus.Draft { cosigning_stake: n } = datum.status
      expect Finite(upper) = validity_range.upper_bound.bound_type
      let cont = continuation(outputs, own_addr, own_hash, p_id)
      and {
        n >= datum.thresholds.accept,
        upper <= datum.start_time + datum.timing_config.draft_length,
        cont.status == ProposalStatus.Voting,
        immutables_ok(cont, datum),
      }
    }
    RejectDraft -> {
      expect ProposalStatus.Draft { .. } = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      and {
        lower >= datum.start_time + datum.timing_config.draft_length,
        quantity_of(mint, own_hash, p_id) == -1,
      }
    }
    EndVotingStage -> {
      expect ProposalStatus.Voting = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      let cont = continuation(outputs, own_addr, own_hash, p_id)
      and {
        lower >= datum.start_time + datum.timing_config.draft_length + datum.timing_config.voting_length,
        cont.status == ProposalStatus.Tally { votes: [] },
        immutables_ok(cont, datum),
      }
    }
    TallyVotes -> {
      expect ProposalStatus.Tally { votes } = datum.status
      expect Finite(upper) = validity_range.upper_bound.bound_type
      let cont = continuation(outputs, own_addr, own_hash, p_id)
      let vote_inputs =
        list.filter(inputs, fn(i) { is_vote_for(vote_policy, p_id, i) })
      let counted = tally(votes, vote_inputs)
      let burned = mint |> assets.tokens(vote_policy) |> dict.to_pairs()
      let all_burned = list.all(burned, fn(entry) { entry.2nd == -1 })
      and {
        upper <= datum.start_time + datum.timing_config.draft_length + datum.timing_config.voting_length + datum.timing_config.tally_length,
        // every consumed vote is refunded to its owner and its NFT burned; the
        // number of burns must match the votes consumed so none slip through
        list.length(vote_inputs) > 0,
        list.length(burned) == list.length(vote_inputs),
        all_burned,
        refunds_ok(vote_inputs, outputs),
        cont.status == ProposalStatus.Tally { votes: counted },
        immutables_ok(cont, datum),
      }
    }
    EndProposal -> {
      expect ProposalStatus.Tally { votes } = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      let time_ok =
        lower >= datum.start_time + datum.timing_config.draft_length + datum.timing_config.voting_length + datum.timing_config.tally_length
      let burned = quantity_of(mint, own_hash, p_id) == -1
      let execution =
        when winner(votes) is {
          Some((option, tally_votes)) ->
            if tally_votes >= datum.thresholds.execute {
              // a strict winner above threshold must run its bound effect
              when pairs.get_first(datum.results, option) is {
                Some(effect) -> pairs.has_key(self.withdrawals, Script(effect))
                None -> True
              }
            } else {
              True
            }
          None -> True
        }
      and {
        time_ok,
        burned,
        execution,
      }
    }
  }
}

/// The continuing proposal output: verifies the NFT is preserved and returns
/// its datum.
fn continuation(
  outputs: List<Output>,
  own_addr: Address,
  own_hash: PolicyId,
  p_id: AssetName,
) -> ProposalDatum {
  expect Some(out) = list.find(outputs, fn(o) { o.address == own_addr })
  expect quantity_of(out.value, own_hash, p_id) == 1
  expect InlineDatum(d) = out.datum
  expect cd: ProposalDatum = d
  cd
}

/// Immutable proposal fields must be preserved across a status transition.
fn immutables_ok(cont: ProposalDatum, datum: ProposalDatum) -> Bool {
  and {
    cont.thresholds == datum.thresholds,
    cont.timing_config == datum.timing_config,
    cont.start_time == datum.start_time,
    cont.results == datum.results,
  }
}

/// Is `input` a vote artifact belonging to proposal `p_id`?
fn is_vote_for(vote_policy: PolicyId, p_id: AssetName, input: Input) -> Bool {
  let has_vote_nft =
    when
      input.output.value |> assets.tokens(vote_policy) |> dict.to_pairs()
    is {
      [Pair(_, q)] -> q == 1
      _ -> False
    }
  if has_vote_nft {
    expect InlineDatum(d) = input.output.datum
    expect vote: VoteDatum = d
    vote.proposal == p_id
  } else {
    False
  }
}

/// Fold the consumed votes into the running tally, weighting each option by the
/// voter's committed stake.
fn tally(prior: Pairs<Int, Int>, vote_inputs: List<Input>) -> Pairs<Int, Int> {
  list.reduce(
    vote_inputs,
    prior,
    fn(acc, input) {
      expect InlineDatum(d) = input.output.datum
      expect vote: VoteDatum = d
      upsert(acc, vote.voted_option, vote.stake)
    },
  )
}

/// Add `weight` to `option`'s tally, preserving key order (new keys appended).
fn upsert(votes: Pairs<Int, Int>, option: Int, weight: Int) -> Pairs<Int, Int> {
  when votes is {
    [] -> [Pair(option, weight)]
    [Pair(k, v), ..rest] ->
      if k == option {
        [Pair(k, v + weight), ..rest]
      } else {
        [Pair(k, v), ..upsert(rest, option, weight)]
      }
  }
}

/// Every consumed vote must be refunded its lovelace to the recorded owner.
fn refunds_ok(vote_inputs: List<Input>, outputs: List<Output>) -> Bool {
  list.all(
    vote_inputs,
    fn(input) {
      expect InlineDatum(d) = input.output.datum
      expect vote: VoteDatum = d
      let owed = lovelace_of(input.output.value)
      list.any(
        outputs,
        fn(o) { o.address == vote.stake_owner && lovelace_of(o.value) >= owed },
      )
    },
  )
}

/// The strictly-winning option and its vote total, or `None` on a tie / no votes.
fn winner(votes: Pairs<Int, Int>) -> Option<(Int, Int)> {
  let (best_option, best_votes, tie) =
    list.reduce(
      votes,
      (None, 0, False),
      fn(acc, entry) {
        let (bo, bv, tie) = acc
        let option = entry.1st
        let v = entry.2nd
        if v > bv {
          (Some(option), v, False)
        } else if v == bv {
          (bo, bv, True)
        } else {
          (bo, bv, tie)
        }
      },
    )
  when best_option is {
    Some(option) ->
      if !tie && best_votes > 0 {
        Some((option, best_votes))
      } else {
        None
      }
    None -> None
  }
}

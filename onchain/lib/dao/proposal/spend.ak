use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/interval.{Finite}
use aiken/option
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, has_any_nft, lovelace_of, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, resolve_input,
}
use dao/types.{
  AcceptDraft, Cosign, CosignProposal, EndProposal, EndVotingStage,
  ProposalDatum, ProposalRedeemer, ProposalStatus, RejectDraft, StakeRedeemer,
  TallyVotes, VoteDatum,
}
use dao/utils.{
  find_continuation_output, find_input_by_policy, single_nft_name,
  spend_redeemer,
}

/// Spending logic for a proposal UTxO. The proposal validator's own hash is the
/// proposal NFT policy id, so the UTxO carries one NFT under `own_hash`.
pub fn validate_proposal_spend(
  vote_policy: PolicyId,
  stake_policy: PolicyId,
  staked_token_policy: PolicyId,
  staked_token_name: AssetName,
  datum: ProposalDatum,
  redeemer: ProposalRedeemer,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = self

  let own_input = resolve_input(inputs, own_ref)
  let own_addr = own_input.address
  expect Script(own_hash) = own_addr.payment_credential
  let p_id = single_nft_name(own_input.value, own_hash)

  let draft_end = datum.start_time + datum.timing_config.draft_length
  let voting_end = draft_end + datum.timing_config.voting_length
  let tally_end = voting_end + datum.timing_config.tally_length

  when redeemer is {
    Cosign -> {
      expect ProposalStatus.Draft { cosigning_stake: n } = datum.status
      let cont = continuation_datum(outputs, own_addr, own_hash, p_id)
      let stake_input = find_input_by_policy(inputs, stake_policy)
      let s = quantity_of(
        stake_input.output.value,
        staked_token_policy,
        staked_token_name,
      )
      let cosigning = {
        expect action: StakeRedeemer = spend_redeemer(
          self,
          stake_input.output_reference,
        )
        action == CosignProposal { proposal_id: p_id }
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
      let cont = continuation_datum(outputs, own_addr, own_hash, p_id)
      and {
        n >= datum.thresholds.accept,
        upper <= draft_end,
        cont.status == ProposalStatus.Voting,
        immutables_ok(cont, datum),
      }
    }
    RejectDraft -> {
      expect ProposalStatus.Draft { .. } = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      and {
        lower >= draft_end,
        quantity_of(mint, own_hash, p_id) == -1,
      }
    }
    EndVotingStage -> {
      expect ProposalStatus.Voting = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      let cont = continuation_datum(outputs, own_addr, own_hash, p_id)
      and {
        lower >= voting_end,
        cont.status == ProposalStatus.Tally {
          votes: list.repeat(0, list.length(datum.results)),
        },
        immutables_ok(cont, datum),
      }
    }
    TallyVotes -> {
      expect ProposalStatus.Tally { votes } = datum.status
      expect Finite(upper) = validity_range.upper_bound.bound_type
      let cont = continuation_datum(outputs, own_addr, own_hash, p_id)
      let (counted, vote_count, refunds_ok) = fold_votes(
        vote_policy,
        p_id,
        inputs,
        outputs,
        votes,
      )
      let burned = mint |> assets.tokens(vote_policy) |> dict.to_pairs()
      and {
        upper <= tally_end,
        // every consumed vote is refunded to its owner and its NFT burned; the
        // number of burns must match the votes consumed so none slip through
        vote_count > 0,
        list.length(burned) == vote_count,
        refunds_ok,
        cont.status == ProposalStatus.Tally { votes: counted },
        immutables_ok(cont, datum),
      }
    }
    EndProposal -> {
      expect ProposalStatus.Tally { votes } = datum.status
      expect Finite(lower) = validity_range.lower_bound.bound_type
      let time_ok = lower >= tally_end
      let burned = quantity_of(mint, own_hash, p_id) == -1
      let execution = when winner(votes) is {
        Some((option, tally_votes)) ->
          if tally_votes >= datum.thresholds.execute {
            // a strict winner above threshold must run its bound effect
            when list.at(datum.results, option) is {
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
fn continuation_datum(
  outputs: List<Output>,
  own_addr: Address,
  own_hash: PolicyId,
  p_id: AssetName,
) -> ProposalDatum {
  let out = find_continuation_output(outputs, own_addr)
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

/// Fold the transaction inputs once: each consumed vote is decoded exactly
/// once, then (if it belongs to this proposal) tallied, counted, and checked
/// for its lovelace refund. Returns (tally, vote_count, refunds_ok).
fn fold_votes(
  vote_policy: PolicyId,
  p_id: AssetName,
  inputs: List<Input>,
  outputs: List<Output>,
  prior: List<Int>,
) -> (List<Int>, Int, Bool) {
  list.reduce(
    inputs,
    (prior, 0, True),
    fn(acc, input) {
      let (tally, count, refunds_ok) = acc
      if has_any_nft(input.output.value, vote_policy) {
        expect InlineDatum(d) = input.output.datum
        expect vote: VoteDatum = d
        if vote.proposal == p_id {
          let owed = lovelace_of(input.output.value)
          let refunded = list.any(
            outputs,
            fn(o) {
              o.address.payment_credential == vote.stake_owner && lovelace_of(
                o.value,
              ) >= owed
            },
          )
          (
            upsert(tally, vote.voted_option, vote.stake),
            count + 1,
            refunds_ok && refunded,
          )
        } else {
          acc
        }
      } else {
        acc
      }
    },
  )
}

/// Add `weight` to the vote total at index `option`, leaving other entries
/// untouched. Out-of-range options are ignored.
fn upsert(votes: List<Int>, option: Int, weight: Int) -> List<Int> {
  list.indexed_map(
    votes,
    fn(index, total) {
      if index == option {
        total + weight
      } else {
        total
      }
    },
  )
}

/// The strictly-winning option and its vote total, or `None` on a tie / no votes.
fn winner(votes: List<Int>) -> Option<(Int, Int)> {
  let (best_option, best_votes, tie) = list.indexed_foldr(
    votes,
    (None, 0, False),
    fn(option, v, acc) {
      let (bo, bv, tie) = acc
      if v > bv {
        (Some(option), v, False)
      } else if v == bv {
        (bo, bv, True)
      } else {
        (bo, bv, tie)
      }
    },
  )
  best_option
    |> option.and_then(
        fn(option) {
          if !tie && best_votes > 0 {
            Some((option, best_votes))
          } else {
            None
          }
        },
      )
}

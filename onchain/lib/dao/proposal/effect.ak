//// Library for poll-effect scripts: the per-option validators referenced by a
//// proposal's `results` field.
////
//// A candidate script must not trust its caller. Being listed as an effect
//// (or even merely having its withdrawal included) says nothing about the
//// poll's outcome — the proposal validator only forces the *winner's* effect
//// to run; it cannot force losers to stay silent, and it cannot prevent a
//// tx from withdrawing from the script outside of `EndProposal`. Candidate
//// scripts therefore close the loop themselves with `am_i_the_winner`, which
//// re-derives the verdict from on-chain state instead of trusting the redeemer:
////
//// 1. locate the proposal UTxO spent with `EndProposal` (pinned to the real
////    proposal validator via its policy id, so spoofed look-alike datums are
////    rejected);
//// 2. confirm the poll is actually closed (`Tally` stage and past the tally
////    deadline, both derived from the datum's locked fields);
//// 3. recompute the strict winner with the very same code the proposal
////    validator uses (`dao/proposal/winner`) and require it clears the
////    `execute` threshold;
//// 4. require that winner's option to point at *this* script;
//// 5. require exactly one such closure, so two simultaneous polls cannot
////    claim one indistinguishable approval;
//// 6. cross-check the redeemer's declared intent — whoever triggers the
////    effect must state which poll and option they believe won (`PollEffectRedeemer`,
////    declared in `dao/types`), and the statement must match reality. The
////    proposal validator enforces the very same declaration on `EndProposal`,
////    so the redeemer is the shared, protocol-checked intent.

use aiken/builtin.{serialise_data}
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, has_any_nft}
use cardano/transaction.{InlineDatum, Input, Transaction}
use dao/proposal/winner.{winner}
use dao/types.{EndProposal, PollEffectRedeemer, ProposalDatum, ProposalStatus}
use dao/utils.{single_nft_name, spend_redeemer, withdraw_redeemer}

/// The unique closed-poll verdict naming `own_hash` as its strict,
/// threshold-clearing winner.
type Verdict {
  Verdict { proposal_id: AssetName, winner_option: Int }
}

/// Does this transaction genuinely close exactly one poll whose strict
/// majority winner — above the proposal's `execute` threshold — is this
/// script? Designed for candidates running under the withdraw-0 convention.
///
/// `proposal_policy` must be pinned at compile time (the proposal validator's
/// own hash); deriving it from transaction data would let anyone forge an
/// approving poll.
pub fn am_i_the_winner(
  proposal_policy: PolicyId,
  own_hash: ScriptHash,
  self: Transaction,
) -> Bool {
  when winning_verdicts(proposal_policy, own_hash, self) is {
    [Verdict { proposal_id, winner_option }] -> {
      expect claim: PollEffectRedeemer = withdraw_redeemer(self, own_hash)
      and {
        claim.proposal_id == proposal_id,
        claim.winner_option == winner_option,
      }
    }
    _ -> False
  }
}

/// Every input of this transaction that closes a poll adjudicated in favour of
/// this script. There may be none, exactly one, or several (which then fails).
fn winning_verdicts(
  proposal_policy: PolicyId,
  own_hash: ScriptHash,
  self: Transaction,
) -> List<Verdict> {
  list.filter_map(
    self.inputs,
    fn(input: Input) {
      let out = input.output
      let looks_like_proposal = has_any_nft(out.value, proposal_policy) && when
        out.address.payment_credential
      is {
        Script(policy) -> policy == proposal_policy
        _ -> False
      }
      if looks_like_proposal {
        verdict_of(proposal_policy, own_hash, input, self)
      } else {
        None
      }
    },
  )
}

fn verdict_of(
  proposal_policy: PolicyId,
  own_hash: ScriptHash,
  input: Input,
  self: Transaction,
) -> Option<Verdict> {
  let out = input.output
  // consumed strictly as a final poll closure; anything else (mid-transition
  // spends, unrelated withdrawals) is simply not our closure, so check it by
  // serialised equality and skip softly rather than crash the whole script
  let redeemer = spend_redeemer(self, input.output_reference)
  if serialise_data(redeemer) != end_proposal_bytes() {
    None
  } else {
    // tampered/impossible shapes inside a proposal-shaped input are treated as
    // fatal rather than skip-worthy: they cannot arise from the real lifecycle
    expect InlineDatum(d) = out.datum
    expect pd: ProposalDatum = d
    let closed = closed_by(pd, self)
    when pd.status is {
      ProposalStatus.Tally { votes } ->
        when winner(votes) is {
          Some((option, tally)) -> {
            let named = list.at(pd.results, option) == Some(own_hash)
            if tally >= pd.thresholds.execute && closed && named {
              Some(
                Verdict {
                  proposal_id: single_nft_name(out.value, proposal_policy),
                  winner_option: option,
                },
              )
            } else {
              None
            }
          }
          _ -> None
        }
      _ -> None
    }
  }
}

/// Serialised `EndProposal`, computed once per call site for soft comparison.
fn end_proposal_bytes() -> ByteArray {
  let r: Data = EndProposal
  serialise_data(r)
}

/// Is the validity range unambiguously past this datum's tally deadline?
fn closed_by(pd: ProposalDatum, self: Transaction) -> Bool {
  when self.validity_range.lower_bound.bound_type is {
    Finite(lower) ->
      lower >= pd.start_time + pd.timing_config.draft_length + pd.timing_config.voting_length + pd.timing_config.tally_length
    _ -> False
  }
}

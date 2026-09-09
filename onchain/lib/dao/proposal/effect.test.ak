use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{Address, Script, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction, placeholder,
}
use dao/proposal/effect.{am_i_the_winner}
use dao/types.{
  EndProposal, ProposalDatum, ProposalStatus, ProposalThresholds,
  ProposalTimingConfig, TallyVotes,
}

// ------------------------------------------------------------------- fixtures

const proposal_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const effect_hash = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const other_hash = #"55555555555555555555555555555555555555555555555555555555"

const imposter_hash =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const start = 500

const tally_end = start + 6000

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn tally() -> ProposalDatum {
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
    start_time: start,
    status: ProposalStatus.Tally { votes: [0, 250] },
    results: [other_hash, effect_hash],
  }
}

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn prop_input(address: Address, name: ByteArray, index: Int) -> Input {
  Input {
    output_reference: ref(index),
    output: Output {
      address,
      value: assets.from_asset(proposal_policy, name, 1),
      datum: InlineDatum(tally()),
      reference_script: None,
    },
  }
}

fn script_prop(name: ByteArray, index: Int) -> Input {
  prop_input(from_script(proposal_policy), name, index)
}

fn imposter_prop(name: ByteArray, index: Int) -> Input {
  prop_input(from_script(imposter_hash), name, index)
}

fn end_r(winner: Option<ScriptHash>) -> Data {
  let r: Data = EndProposal { winner }
  r
}

fn tally_votes_r() -> Data {
  let r: Data = TallyVotes
  r
}

/// A closure transaction where the poll ends won by this script: the single
/// proposal UTxO is consumed with `EndProposal { winner: Some(effect_hash) }`.
fn closure_tx(winner: Option<ScriptHash>) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [script_prop("PROP", 0)],
    mint: assets.from_asset(proposal_policy, "PROP", -1),
    withdrawals: [Pair(Script(effect_hash), 0)],
    redeemers: [Pair(Spend(ref(0)), end_r(winner))],
    validity_range: interval.after(tally_end),
  }
}

// ------------------------------------------------------------------ happy path

test am_i_the_winner_ok() {
  am_i_the_winner(proposal_policy, effect_hash, closure_tx(Some(effect_hash)))
}

// ----------------------------------------------------------------- adversarial

test rejects_losing_candidate_script() {
  // the closure names another listed effect as the winner
  !am_i_the_winner(proposal_policy, effect_hash, closure_tx(Some(other_hash)))
}

test rejects_closed_without_execution() {
  // the poll closed with no winner above the execute threshold: nothing runs
  !am_i_the_winner(proposal_policy, effect_hash, closure_tx(None))
}

test rejects_missing_end_proposal_closure() {
  // the proposal UTxO changes state within this tx; that is no closure
  let tx = Transaction {
    ..closure_tx(Some(effect_hash)),
    redeemers: [Pair(Spend(ref(0)), tally_votes_r())],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_spoofed_proposal_utxo() {
  // an imposter UTxO shaped like a poll but sitting behind another script
  let tx = Transaction {
    ..placeholder,
    inputs: [imposter_prop("PROP", 0)],
    withdrawals: [Pair(Script(effect_hash), 0)],
    redeemers: [Pair(Spend(ref(0)), end_r(Some(effect_hash)))],
    validity_range: interval.after(tally_end),
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_outside_any_closure() {
  // a bare withdrawal far away from any poll
  let bare = Transaction {
    ..placeholder,
    withdrawals: [Pair(Script(effect_hash), 0)],
  }
  !am_i_the_winner(proposal_policy, effect_hash, bare)
}

test rejects_two_simultaneous_closures() {
  // two polls close at once and both would name us: our single approval is
  // ambiguous, so refuse
  let tx = Transaction {
    ..closure_tx(Some(effect_hash)),
    inputs: [script_prop("P1", 0), script_prop("P2", 1)],
    redeemers: [
      Pair(Spend(ref(0)), end_r(Some(effect_hash))),
      Pair(Spend(ref(1)), end_r(Some(effect_hash))),
    ],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_mid_transition_proposal_input() {
  // another proposal of the same DAO is spent in the same tx: with the strict
  // single-proposal-input rule, the candidate refuses to run
  let tx = Transaction {
    ..closure_tx(Some(effect_hash)),
    inputs: [script_prop("PROP", 0), script_prop("OTHER", 1)],
    redeemers: [
      Pair(Spend(ref(0)), end_r(Some(effect_hash))),
      Pair(Spend(ref(1)), tally_votes_r()),
    ],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

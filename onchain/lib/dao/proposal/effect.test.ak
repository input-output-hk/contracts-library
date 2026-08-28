use aiken/crypto.{ScriptHash}
use aiken/interval
use cardano/address.{Address, Script, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction, Withdraw,
  placeholder,
}
use dao/proposal/effect.{am_i_the_winner}
use dao/types.{
  EndProposal, ExecuteWinner, ProposalDatum, ProposalStatus, ProposalThresholds,
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

/// Thresholds as in the shared proposal fixtures: execute = 200.
fn tally(votes: List<Int>, results: List<ScriptHash>) -> ProposalDatum {
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
    status: ProposalStatus.Tally { votes },
    results,
  }
}

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn prop_input(
  address: Address,
  name: ByteArray,
  d: ProposalDatum,
  index: Int,
) -> Input {
  Input {
    output_reference: ref(index),
    output: Output {
      address,
      value: assets.from_asset(proposal_policy, name, 1),
      datum: InlineDatum(d),
      reference_script: None,
    },
  }
}

fn script_prop(name: ByteArray, d: ProposalDatum, index: Int) -> Input {
  prop_input(from_script(proposal_policy), name, d, index)
}

fn imposter_prop(name: ByteArray, d: ProposalDatum, index: Int) -> Input {
  prop_input(from_script(imposter_hash), name, d, index)
}

fn withdraw_r(option: Int) -> Data {
  let claim: Data = ExecuteWinner { proposal_id: "PROP", winner_option: option }
  claim
}

fn end_proposal_r() -> Data {
  let r: Data = EndProposal
  r
}

fn tally_votes_r() -> Data {
  let r: Data = TallyVotes
  r
}

/// A closure transaction where the poll ends strictly won by option 1
/// (`effect_hash`), carrying matching intent in the withdrawal redeemer.
fn closure_tx(votes: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [
      script_prop("PROP", tally([0, votes], [other_hash, effect_hash]), 0),
    ],
    mint: assets.from_asset(proposal_policy, "PROP", -1),
    withdrawals: [Pair(Script(effect_hash), 0)],
    redeemers: [
      Pair(Spend(ref(0)), end_proposal_r()),
      Pair(Withdraw(Script(effect_hash)), withdraw_r(1)),
    ],
    validity_range: interval.after(tally_end),
  }
}

// ------------------------------------------------------------------ happy path

test am_i_the_winner_ok() {
  am_i_the_winner(proposal_policy, effect_hash, closure_tx(250))
}

// ----------------------------------------------------------------- adversarial

test rejects_wrong_claimed_option() {
  let tx = Transaction {
    ..closure_tx(250),
    redeemers: [
      Pair(Spend(ref(0)), end_proposal_r()),
      Pair(Withdraw(Script(effect_hash)), withdraw_r(0)),
    ],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_below_execute_threshold() {
  // strict winner, yet short of quorum: nobody gets to execute
  !am_i_the_winner(proposal_policy, effect_hash, closure_tx(150))
}

test rejects_before_tally_deadline() {
  let tx = Transaction {
    ..closure_tx(250),
    validity_range: interval.after(start + 5000),
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_tie() {
  let d = tally([0, 250, 250], [other_hash, effect_hash, other_hash])
  let tx = Transaction {
    ..closure_tx(250),
    inputs: [script_prop("PROP", d, 0)],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_losing_candidate_script() {
  // another listed effect asks whether IT won
  !am_i_the_winner(proposal_policy, other_hash, closure_tx(250))
}

test rejects_missing_end_proposal_closure() {
  // the proposal UTxO changes state within this tx; that is no closure
  let tx = Transaction {
    ..closure_tx(250),
    redeemers: [
      Pair(Spend(ref(0)), tally_votes_r()),
      Pair(Withdraw(Script(effect_hash)), withdraw_r(1)),
    ],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_spoofed_proposal_utxo() {
  // an imposter UTxO shaped like a poll but sitting behind another script
  let imposter = imposter_prop(
    "PROP",
    tally([0, 99999999], [other_hash, effect_hash]),
    7,
  )
  let tx = Transaction {
    ..closure_tx(0),
    inputs: [imposter],
    redeemers: [
      Pair(Spend(ref(7)), end_proposal_r()),
      Pair(Withdraw(Script(effect_hash)), withdraw_r(1)),
    ],
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

test rejects_outside_any_closure() {
  // a bare withdrawal far away from any poll
  let bare = Transaction {
    ..placeholder,
    withdrawals: [Pair(Script(effect_hash), 0)],
    redeemers: [Pair(Withdraw(Script(effect_hash)), withdraw_r(1))],
  }
  !am_i_the_winner(proposal_policy, effect_hash, bare)
}

test rejects_two_simultaneous_closures() {
  // two polls close at once and both would name us: our single approval is
  // ambiguous, so refuse
  let p1 = script_prop("P1", tally([0, 300], [other_hash, effect_hash]), 0)
  let p2 = script_prop("P2", tally([0, 400], [other_hash, effect_hash]), 1)
  let claim: Data = ExecuteWinner { proposal_id: "P1", winner_option: 1 }
  let tx = Transaction {
    ..placeholder,
    inputs: [p1, p2],
    withdrawals: [Pair(Script(effect_hash), 0)],
    redeemers: [
      Pair(Spend(ref(0)), end_proposal_r()),
      Pair(Spend(ref(1)), end_proposal_r()),
      Pair(Withdraw(Script(effect_hash)), claim),
    ],
    validity_range: interval.after(tally_end),
  }
  !am_i_the_winner(proposal_policy, effect_hash, tx)
}

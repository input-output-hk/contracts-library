use aiken/fuzz
use aiken/interval
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Spend,
  Transaction, placeholder,
}
use dao/proposal/mint.{validate_create_proposal}
use dao/proposal/spend.{validate_proposal_spend}
use dao/types.{
  AcceptDraft, Cosign, CosignProposal, CreateProposal, DaoSettings, EndProposal,
  EndVotingStage, ProposalDatum, ProposalRedeemer, ProposalStatus,
  ProposalThresholds, ProposalTimingConfig, RejectDraft, TallyVotes, VoteDatum,
  Voting,
}
use dao/utils.{get_dao_settings, proposal_token_name}
use settings/types as settings_types

// ------------------------------------------------------------------- fixtures

const proposal_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const stake_hash = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const vote_policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const gov_policy = #"22222222222222222222222222222222222222222222222222222222"

const gov_name = "GOV"

const settings_policy =
  #"33333333333333333333333333333333333333333333333333333333"

const settings_name = "SETTINGS"

const effect_hash = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const voter_hash = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const prop_nft = "PROP"

const stake_nft = "S"

const start = 500

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn thresholds_with_create(create: Int) -> ProposalThresholds {
  ProposalThresholds {
    create,
    cosign: 50,
    accept: 100,
    vote: 10,
    execute: 200,
  }
}

fn thresholds() -> ProposalThresholds {
  thresholds_with_create(100)
}

fn timings() -> ProposalTimingConfig {
  ProposalTimingConfig {
    draft_length: 1000,
    voting_length: 2000,
    tally_length: 3000,
  }
}

fn dao_settings() -> DaoSettings {
  DaoSettings {
    thresholds: thresholds(),
    timings: timings(),
    stake_validator: stake_hash,
    proposal_validator: proposal_policy,
    vote_validator: vote_policy,
  }
}

fn dao_settings_for_create(create: Int) -> DaoSettings {
  DaoSettings {
    thresholds: thresholds_with_create(create),
    timings: timings(),
    stake_validator: stake_hash,
    proposal_validator: proposal_policy,
    vote_validator: vote_policy,
  }
}

fn settings_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 99 }
}

fn settings_input() -> Input {
  Input {
    output_reference: settings_ref(),
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_asset(settings_policy, settings_name, 1),
      datum: InlineDatum(
        settings_types.SettingsDatum {
          current: dao_settings(),
          next: None,
          next_apply: None,
        },
      ),
      reference_script: None,
    },
  }
}

fn settings_input_create(create: Int) -> Input {
  Input {
    output_reference: settings_ref(),
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_asset(settings_policy, settings_name, 1),
      datum: InlineDatum(
        settings_types.SettingsDatum {
          current: dao_settings_for_create(create),
          next: None,
          next_apply: None,
        },
      ),
      reference_script: None,
    },
  }
}

fn prop_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn datum(
  status: ProposalStatus,
  results: Pairs<Int, ByteArray>,
) -> ProposalDatum {
  ProposalDatum {
    thresholds: thresholds(),
    timing_config: timings(),
    start_time: start,
    status,
    results,
  }
}

fn prop_input(d: ProposalDatum) -> Input {
  Input {
    output_reference: prop_ref(),
    output: Output {
      address: from_script(proposal_policy),
      value: assets.from_asset(proposal_policy, prop_nft, 1),
      datum: InlineDatum(d),
      reference_script: None,
    },
  }
}

fn prop_output(d: ProposalDatum) -> Output {
  Output {
    address: from_script(proposal_policy),
    value: assets.from_asset(proposal_policy, prop_nft, 1),
    datum: InlineDatum(d),
    reference_script: None,
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

fn vote_ref(i: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: i }
}

fn vote_input(i: Int, option: Int, s: Int, lovelace: Int) -> Input {
  Input {
    output_reference: vote_ref(i),
    output: Output {
      address: from_script(vote_policy),
      value: assets.from_lovelace(lovelace)
        |> assets.add(vote_policy, "V", 1),
      datum: InlineDatum(
        VoteDatum {
          stake_owner: Script(voter_hash),
          proposal: prop_nft,
          voted_option: option,
          stake: s,
        },
      ),
      reference_script: None,
    },
  }
}

fn refund(lovelace: Int) -> Output {
  Output {
    address: from_script(voter_hash),
    value: assets.from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn spend(d: ProposalDatum, r: ProposalRedeemer, self: Transaction) -> Bool {
  validate_proposal_spend(
    vote_policy,
    stake_hash,
    gov_policy,
    gov_name,
    d,
    r,
    prop_ref(),
    self,
  )
}

fn mint_stake_value(stake: Int) -> assets.Value {
  assets.from_asset(stake_hash, stake_nft, 1)
    |> assets.add(gov_policy, gov_name, stake)
}

fn mint_stake_input(index: Int, stake: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(stake_hash),
      value: mint_stake_value(stake),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn mint_proposal_datum(create: Int, stake: Int, now: Int) -> ProposalDatum {
  ProposalDatum {
    thresholds: thresholds_with_create(create),
    timing_config: timings(),
    start_time: now,
    status: ProposalStatus.Draft { cosigning_stake: stake },
    results: [],
  }
}

fn proposal_output_named(token_name: ByteArray, d: ProposalDatum) -> Output {
  Output {
    address: from_script(proposal_policy),
    value: assets.from_asset(proposal_policy, token_name, 1),
    datum: InlineDatum(d),
    reference_script: None,
  }
}

// A well-formed CreateProposal transaction. `stake` is the staked-token amount
// held by the creating stake UTxO.
fn create_tx(create: Int, stake: Int, now: Int) -> Transaction {
  let stake_in = mint_stake_input(0, stake)
  let token_name = proposal_token_name(stake_in.output_reference)
  let create_r: Data = CreateProposal
  Transaction {
    ..placeholder,
    inputs: [stake_in],
    reference_inputs: [settings_input_create(create)],
    outputs: [proposal_output_named(token_name, mint_proposal_datum(create, stake, now))],
    mint: assets.from_asset(proposal_policy, token_name, 1),
    redeemers: [Pair(Spend(stake_in.output_reference), create_r)],
    validity_range: interval.after(now),
  }
}

fn validate_mint(tx: Transaction) -> Bool {
  let settings = get_dao_settings(tx, settings_ref(), settings_name)
  validate_create_proposal(settings, gov_policy, gov_name, proposal_policy, tx)
}

// --------------------------------------------------------------------- Cosign

test cosign_ok() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 10 }, [])
  let cont =
    prop_output(datum(ProposalStatus.Draft { cosigning_stake: 15 }, []))
  let cosign_r: Data = CosignProposal
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d), stake_input(5)],
      outputs: [cont],
      redeemers: [Pair(Spend(stake_ref()), cosign_r)],
    }
  spend(d, Cosign, tx)
}

test rejects_cosign_wrong_new_stake() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 10 }, [])
  // continuation records the wrong running total (should be 15)
  let cont =
    prop_output(datum(ProposalStatus.Draft { cosigning_stake: 20 }, []))
  let cosign_r: Data = CosignProposal
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d), stake_input(5)],
      outputs: [cont],
      redeemers: [Pair(Spend(stake_ref()), cosign_r)],
    }
  !spend(d, Cosign, tx)
}

// ---------------------------------------------------------------- AcceptDraft

test accept_draft_ok() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 120 }, [])
  let cont = prop_output(datum(ProposalStatus.Voting, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      outputs: [cont],
      validity_range: interval.before(start + 1000),
    }
  spend(d, AcceptDraft, tx)
}

test rejects_accept_below_threshold() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 80 }, [])
  let cont = prop_output(datum(ProposalStatus.Voting, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      outputs: [cont],
      validity_range: interval.before(start + 1000),
    }
  !spend(d, AcceptDraft, tx)
}

test rejects_accept_after_draft_window() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 120 }, [])
  let cont = prop_output(datum(ProposalStatus.Voting, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      outputs: [cont],
      validity_range: interval.before(start + 2000),
    }
  !spend(d, AcceptDraft, tx)
}

// ---------------------------------------------------------------- RejectDraft

test reject_draft_ok() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 10 }, [])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 1000),
    }
  spend(d, RejectDraft, tx)
}

test rejects_reject_before_draft_window() {
  let d = datum(ProposalStatus.Draft { cosigning_stake: 10 }, [])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 500),
    }
  !spend(d, RejectDraft, tx)
}

// -------------------------------------------------------------- EndVotingStage

test end_voting_ok() {
  let d = datum(ProposalStatus.Voting, [])
  let cont = prop_output(datum(ProposalStatus.Tally { votes: [] }, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      outputs: [cont],
      validity_range: interval.after(start + 3000),
    }
  spend(d, EndVotingStage, tx)
}

test rejects_end_voting_too_early() {
  let d = datum(ProposalStatus.Voting, [])
  let cont = prop_output(datum(ProposalStatus.Tally { votes: [] }, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      outputs: [cont],
      validity_range: interval.after(start + 2000),
    }
  !spend(d, EndVotingStage, tx)
}

// ----------------------------------------------------------------- TallyVotes

test tally_votes_ok() {
  let d = datum(ProposalStatus.Tally { votes: [] }, [])
  let cont =
    prop_output(datum(ProposalStatus.Tally { votes: [Pair(1, 5)] }, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d), vote_input(2, 1, 5, 2_000_000)],
      reference_inputs: [settings_input()],
      outputs: [cont, refund(2_000_000)],
      mint: assets.from_asset(vote_policy, "V", -1),
      validity_range: interval.before(start + 6000),
    }
  spend(d, TallyVotes, tx)
}

test rejects_tally_without_refund() {
  let d = datum(ProposalStatus.Tally { votes: [] }, [])
  let cont =
    prop_output(datum(ProposalStatus.Tally { votes: [Pair(1, 5)] }, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d), vote_input(2, 1, 5, 2_000_000)],
      reference_inputs: [settings_input()],
      outputs: [cont],
      mint: assets.from_asset(vote_policy, "V", -1),
      validity_range: interval.before(start + 6000),
    }
  !spend(d, TallyVotes, tx)
}

test rejects_tally_without_burn() {
  let d = datum(ProposalStatus.Tally { votes: [] }, [])
  let cont =
    prop_output(datum(ProposalStatus.Tally { votes: [Pair(1, 5)] }, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d), vote_input(2, 1, 5, 2_000_000)],
      reference_inputs: [settings_input()],
      outputs: [cont, refund(2_000_000)],
      validity_range: interval.before(start + 6000),
    }
  !spend(d, TallyVotes, tx)
}

// ---------------------------------------------------------------- EndProposal

test end_proposal_below_execute_ok() {
  // winner has 150 votes (< execute threshold 200): no effect required
  let d = datum(ProposalStatus.Tally { votes: [Pair(1, 150)] }, [])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 6000),
    }
  spend(d, EndProposal, tx)
}

test end_proposal_executes_effect_ok() {
  let d =
    datum(
      ProposalStatus.Tally { votes: [Pair(1, 250)] },
      [Pair(1, effect_hash)],
    )
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      withdrawals: [Pair(Script(effect_hash), 0)],
      validity_range: interval.after(start + 6000),
    }
  spend(d, EndProposal, tx)
}

test rejects_end_proposal_missing_effect() {
  let d =
    datum(
      ProposalStatus.Tally { votes: [Pair(1, 250)] },
      [Pair(1, effect_hash)],
    )
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 6000),
    }
  !spend(d, EndProposal, tx)
}

test rejects_end_proposal_too_early() {
  let d = datum(ProposalStatus.Tally { votes: [Pair(1, 150)] }, [])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 5000),
    }
  !spend(d, EndProposal, tx)
}

test end_proposal_tie_needs_no_effect() {
  // a tie yields no winner, so no effect withdrawal is required
  let d =
    datum(
      ProposalStatus.Tally { votes: [Pair(1, 250), Pair(2, 250)] },
      [Pair(1, effect_hash)],
    )
  let tx =
    Transaction {
      ..placeholder,
      inputs: [prop_input(d)],
      mint: assets.from_asset(proposal_policy, prop_nft, -1),
      validity_range: interval.after(start + 6000),
    }
  spend(d, EndProposal, tx)
}

// ------------------------------------------------------------- mint happy path

test create_proposal_ok() {
  validate_mint(create_tx(100, 100, 5000))
}

test stake_above_threshold_ok() {
  validate_mint(create_tx(100, 250, 5000))
}

test stake_at_threshold_boundary_ok() {
  validate_mint(create_tx(100, 100, 5000))
}

// ----------------------------------------------------------- mint adversarial

test rejects_stake_below_threshold() fail {
  validate_mint(create_tx(100, 99, 5000))
}

test rejects_wrong_thresholds_in_datum() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated = mint_proposal_datum(200, 100, 5000)
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_wrong_timings_in_datum() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum {
      ..mint_proposal_datum(100, 100, 5000),
      timing_config: ProposalTimingConfig {
        draft_length: 9999,
        voting_length: 2000,
        tally_length: 3000,
      },
    }
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_wrong_start_time() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum { ..mint_proposal_datum(100, 100, 5000), start_time: 5001 }
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_wrong_cosigning_stake() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum {
      ..mint_proposal_datum(100, 100, 5000),
      status: ProposalStatus.Draft { cosigning_stake: 1000 },
    }
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_non_draft_status() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum { ..mint_proposal_datum(100, 100, 5000), status: Voting }
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_non_empty_results() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum {
      ..mint_proposal_datum(100, 100, 5000),
      results: [Pair(1, proposal_policy)],
    }
  validate_mint(
    Transaction { ..tx, outputs: [proposal_output_named(token_name, mutated)] },
  )
}

test rejects_wrong_address() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let bad_output =
    Output {
      ..proposal_output_named(token_name, mint_proposal_datum(100, 100, 5000)),
      address: from_script(stake_hash),
    }
  validate_mint(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_reference_script() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let bad_output =
    Output {
      ..proposal_output_named(token_name, mint_proposal_datum(100, 100, 5000)),
      reference_script: Some(proposal_policy),
    }
  validate_mint(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_wrong_token_name() fail {
  let tx = create_tx(100, 100, 5000)
  validate_mint(
    Transaction { ..tx, mint: assets.from_asset(proposal_policy, "WRONG", 1) },
  )
}

test rejects_wrong_mint_quantity() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  validate_mint(
    Transaction { ..tx, mint: assets.from_asset(proposal_policy, token_name, 2) },
  )
}

test rejects_missing_stake_input() fail {
  let tx = create_tx(100, 100, 5000)
  validate_mint(Transaction { ..tx, inputs: [] })
}

test rejects_missing_settings_ref() fail {
  let tx = create_tx(100, 100, 5000)
  validate_mint(Transaction { ..tx, reference_inputs: [] })
}

test rejects_datum_hash_output() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let bad_output =
    Output {
      ..proposal_output_named(token_name, mint_proposal_datum(100, 100, 5000)),
      datum: DatumHash(tx_id),
    }
  validate_mint(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_unbounded_validity_range() fail {
  let tx = create_tx(100, 100, 5000)
  validate_mint(Transaction { ..tx, validity_range: interval.everything })
}

// ------------------------------------------------------------------- mint fuzz

fn scenario() -> Fuzzer<(Int, Int)> {
  fuzz.int_between(1, 1_000_000)
    |> fuzz.and_then(
        fn(create) {
          fuzz.int_between(0, 1_000_000)
            |> fuzz.map(fn(extra) { (create, create + extra) })
        },
      )
}

test prop_accepts_when_stake_meets_threshold((create, stake) via scenario()) {
  validate_mint(create_tx(create, stake, 5000))
}

test prop_start_time_reflected_in_datum((create, stake) via scenario()) {
  // The datum's start_time must equal the validity lower bound; verify the
  // validator accepts any `now` as long as the datum mirrors it.
  let now = stake + create
  validate_mint(create_tx(create, stake, now))
}

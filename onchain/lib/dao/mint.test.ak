use aiken/fuzz
use aiken/interval
use cardano/address.{from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use dao/mint.{validate_create_proposal}
use dao/types.{
  DaoSettings, ProposalDatum, ProposalStatus, ProposalThresholds,
  ProposalTimingConfig, Voting,
}
use dao/utils.{proposal_token_name, proposal_token_name}
use settings/types as settings_types

// ------------------------------------------------------------------- fixtures

const own_policy = #"99999999999999999999999999999999999999999999999999999999"

const stake_nft_policy =
  #"11111111111111111111111111111111111111111111111111111111"

const stake_nft_name = "STAKE"

const stake_token_policy =
  #"22222222222222222222222222222222222222222222222222222222"

const stake_token_name = "GOV"

const settings_policy =
  #"33333333333333333333333333333333333333333333333333333333"

const settings_name = "SETTINGS"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn thresholds(create: Int) -> ProposalThresholds {
  ProposalThresholds { create, cosign: 50, accept: 100, vote: 10, execute: 200 }
}

fn timings() -> ProposalTimingConfig {
  ProposalTimingConfig {
    draft_length: 1000,
    voting_length: 2000,
    tally_length: 3000,
  }
}

fn daosettings(create: Int) -> DaoSettings {
  DaoSettings { thresholds: thresholds(create), timings: timings() }
}

fn settings_datum(create: Int) -> settings_types.SettingsDatum {
  settings_types.SettingsDatum {
    current: daosettings(create),
    next: None,
    next_apply: None,
  }
}

fn settings_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 99 }
}

fn stake_value(stake: Int) -> Value {
  assets.from_asset(stake_nft_policy, stake_nft_name, 1)
    |> assets.add(stake_token_policy, stake_token_name, stake)
}

fn stake_input(index: Int, stake: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(stake_nft_policy),
      value: stake_value(stake),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn settings_input(create: Int) -> Input {
  Input {
    output_reference: settings_ref(),
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_asset(settings_policy, settings_name, 1),
      datum: InlineDatum(settings_datum(create)),
      reference_script: None,
    },
  }
}

fn proposal_datum(create: Int, stake: Int, now: Int) -> ProposalDatum {
  ProposalDatum {
    thresholds: thresholds(create),
    timing_config: timings(),
    start_time: now,
    status: ProposalStatus.Draft { cosigning_stake: stake },
    results: [],
  }
}

fn proposal_output(token_name: ByteArray, d: ProposalDatum) -> Output {
  Output {
    address: from_script(own_policy),
    value: assets.from_asset(own_policy, token_name, 1),
    datum: InlineDatum(d),
    reference_script: None,
  }
}

// A well-formed CreateProposal transaction. `stake` is the staked-token amount
// held by the creating stake UTxO.
fn create_tx(create: Int, stake: Int, now: Int) -> Transaction {
  let stake_in = stake_input(0, stake)
  let token_name = proposal_token_name(stake_in.output_reference)
  Transaction {
    ..placeholder,
    inputs: [stake_in],
    reference_inputs: [settings_input(create)],
    outputs: [proposal_output(token_name, proposal_datum(create, stake, now))],
    mint: assets.from_asset(own_policy, token_name, 1),
    validity_range: interval.after(now),
  }
}

fn validate(tx: Transaction) -> Bool {
  validate_create_proposal(
    settings_ref(),
    stake_nft_policy,
    stake_nft_name,
    stake_token_policy,
    stake_token_name,
    own_policy,
    tx,
  )
}

// ------------------------------------------------------------- happy path

test create_proposal_ok() {
  validate(create_tx(100, 100, 5000))
}

test stake_above_threshold_ok() {
  validate(create_tx(100, 250, 5000))
}

test stake_at_threshold_boundary_ok() {
  validate(create_tx(100, 100, 5000))
}

// ----------------------------------------------------------- adversarial

test rejects_stake_below_threshold() fail {
  validate(create_tx(100, 99, 5000))
}

test rejects_wrong_thresholds_in_datum() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated = proposal_datum(200, 100, 5000)
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
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
      ..proposal_datum(100, 100, 5000),
      timing_config: ProposalTimingConfig {
        draft_length: 9999,
        voting_length: 2000,
        tally_length: 3000,
      },
    }
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
  )
}

test rejects_wrong_start_time() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum { ..proposal_datum(100, 100, 5000), start_time: 5001 }
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
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
      ..proposal_datum(100, 100, 5000),
      status: ProposalStatus.Draft { cosigning_stake: 1000 },
    }
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
  )
}

test rejects_non_draft_status() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let mutated =
    ProposalDatum { ..proposal_datum(100, 100, 5000), status: Voting }
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
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
      ..proposal_datum(100, 100, 5000),
      results: [Pair(1, own_policy)],
    }
  validate(
    Transaction { ..tx, outputs: [proposal_output(token_name, mutated)] },
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
      ..proposal_output(token_name, proposal_datum(100, 100, 5000)),
      address: from_script(stake_nft_policy),
    }
  validate(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_reference_script() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let bad_output =
    Output {
      ..proposal_output(token_name, proposal_datum(100, 100, 5000)),
      reference_script: Some(own_policy),
    }
  validate(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_wrong_token_name() fail {
  let tx = create_tx(100, 100, 5000)
  validate(
    Transaction { ..tx, mint: assets.from_asset(own_policy, "WRONG", 1) },
  )
}

test rejects_wrong_mint_quantity() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  validate(
    Transaction { ..tx, mint: assets.from_asset(own_policy, token_name, 2) },
  )
}

test rejects_missing_stake_input() fail {
  let tx = create_tx(100, 100, 5000)
  validate(Transaction { ..tx, inputs: [] })
}

test rejects_missing_settings_ref() fail {
  let tx = create_tx(100, 100, 5000)
  validate(Transaction { ..tx, reference_inputs: [] })
}

test rejects_datum_hash_output() fail {
  let tx = create_tx(100, 100, 5000)
  let token_name =
    proposal_token_name(
      OutputReference { transaction_id: tx_id, output_index: 0 },
    )
  let bad_output =
    Output {
      ..proposal_output(token_name, proposal_datum(100, 100, 5000)),
      datum: DatumHash(tx_id),
    }
  validate(Transaction { ..tx, outputs: [bad_output] })
}

test rejects_unbounded_validity_range() fail {
  let tx = create_tx(100, 100, 5000)
  validate(Transaction { ..tx, validity_range: interval.everything })
}

// ------------------------------------------------------------------- fuzz

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
  validate(create_tx(create, stake, 5000))
}

test prop_start_time_reflected_in_datum((create, stake) via scenario()) {
  // The datum's start_time must equal the validity lower bound; verify the
  // validator accepts any `now` as long as the datum mirrors it.
  let now = stake + create
  validate(create_tx(create, stake, now))
}

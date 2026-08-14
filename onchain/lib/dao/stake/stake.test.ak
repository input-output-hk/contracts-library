use aiken/interval
use cardano/address.{Credential, VerificationKey, from_script}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use dao/stake/mint.{validate_close_position, validate_create_position}
use dao/stake/spend.{validate_stake_spend}
use dao/types.{
  ClosePosition, CosignProposal, CreateProposal, DaoSettings, DelegateTo,
  Deposit, ProposalDatum, ProposalStatus, ProposalThresholds,
  ProposalTimingConfig, StakePositionDatum, StakeRedeemer, VoteProposal,
  Withdraw,
}
use dao/utils.{nft_name_from_ref, proposal_token_name}
use settings/types as settings_types

// ------------------------------------------------------------------- fixtures

const stake_hash = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const proposal_policy =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const vote_policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const gov_policy = #"22222222222222222222222222222222222222222222222222222222"

const gov_name = "GOV"

const settings_policy =
  #"33333333333333333333333333333333333333333333333333333333"

const settings_name = "SETTINGS"

const owner_hash = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const delegatee_hash =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const pos_nft = "POS"

const prop_nft = "PROP"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn owner() -> Credential {
  VerificationKey(owner_hash)
}

fn thresholds() -> ProposalThresholds {
  ProposalThresholds {
    create: 100,
    cosign: 50,
    accept: 100,
    vote: 10,
    execute: 200,
  }
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

fn pos_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn pos_value(stake: Int) -> Value {
  assets.from_asset(stake_hash, pos_nft, 1)
    |> assets.add(gov_policy, gov_name, stake)
}

fn stake_datum(
  delegatee: Option<Credential>,
  locks: List<(ByteArray, Int, Int)>,
) {
  StakePositionDatum { owner: owner(), delegatee, locks }
}

fn pos_input(stake: Int) -> Input {
  Input {
    output_reference: pos_ref(),
    output: Output {
      address: from_script(stake_hash),
      value: pos_value(stake),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn pos_output(stake: Int, d: StakePositionDatum) -> Output {
  Output {
    address: from_script(stake_hash),
    value: pos_value(stake),
    datum: InlineDatum(d),
    reference_script: None,
  }
}

fn proposal_input_draft(start: Int) -> Input {
  proposal_utxo(ProposalStatus.Draft { cosigning_stake: 0 }, start)
}

fn proposal_ref_voting(start: Int) -> Input {
  proposal_utxo(ProposalStatus.Voting, start)
}

fn proposal_utxo(status: ProposalStatus, start: Int) -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 5 },
    output: Output {
      address: from_script(proposal_policy),
      value: assets.from_asset(proposal_policy, prop_nft, 1),
      datum: InlineDatum(
        ProposalDatum {
          thresholds: thresholds(),
          timing_config: timings(),
          start_time: start,
          status,
          results: [],
        },
      ),
      reference_script: None,
    },
  }
}

fn spend(d: StakePositionDatum, r: StakeRedeemer, self: Transaction) -> Bool {
  validate_stake_spend(
    gov_policy,
    gov_name,
    settings_ref(),
    settings_name,
    d,
    r,
    pos_ref(),
    self,
  )
}

// ------------------------------------------------------------------- Deposit

test deposit_ok() {
  let d = stake_datum(None, [])
  let out = pos_output(20, stake_datum(None, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  spend(d, Deposit, tx)
}

test rejects_deposit_unsigned() {
  let d = stake_datum(None, [])
  let out = pos_output(20, stake_datum(None, []))
  let tx =
    Transaction { ..placeholder, inputs: [pos_input(10)], outputs: [out] }
  !spend(d, Deposit, tx)
}

test rejects_deposit_that_removes_stake() {
  let d = stake_datum(None, [])
  // continuation carries less stake than the input — disallowed for a deposit
  let out = pos_output(5, stake_datum(None, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  !spend(d, Deposit, tx)
}

// ------------------------------------------------------------------ Delegate

test delegate_ok() {
  let d = stake_datum(None, [])
  let out =
    pos_output(10, stake_datum(Some(VerificationKey(delegatee_hash)), []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  spend(d, DelegateTo { delegatee: Some(VerificationKey(delegatee_hash)) }, tx)
}

test rejects_delegate_that_changes_stake() {
  let d = stake_datum(None, [])
  let out =
    pos_output(20, stake_datum(Some(VerificationKey(delegatee_hash)), []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  !spend(d, DelegateTo { delegatee: Some(VerificationKey(delegatee_hash)) }, tx)
}

// ------------------------------------------------------------------ Withdraw

test withdraw_free_ok() {
  let d = stake_datum(None, [])
  let out = pos_output(6, stake_datum(None, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  spend(d, Withdraw { amount: 4 }, tx)
}

test rejects_withdraw_of_locked_stake() {
  // a live lock freezes 8 tokens; only 2 of 10 are free
  let locks = [(prop_nft, 2000, 8)]
  let d = stake_datum(None, locks)
  let out = pos_output(6, stake_datum(None, locks))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  !spend(d, Withdraw { amount: 4 }, tx)
}

test withdraw_prunes_expired_lock() {
  // lock unlock_time 400 <= now 500 → pruned, all 10 become free
  let d = stake_datum(None, [(prop_nft, 400, 8)])
  let out = pos_output(2, stake_datum(None, []))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      outputs: [out],
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  spend(d, Withdraw { amount: 8 }, tx)
}

// ------------------------------------------------------------- ClosePosition

test close_position_ok() {
  let d = stake_datum(None, [(prop_nft, 400, 8)])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      mint: assets.from_asset(stake_hash, pos_nft, -1),
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  spend(d, ClosePosition, tx)
}

test rejects_close_with_live_lock() {
  let d = stake_datum(None, [(prop_nft, 900, 8)])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      mint: assets.from_asset(stake_hash, pos_nft, -1),
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  !spend(d, ClosePosition, tx)
}

test rejects_close_without_burn() {
  let d = stake_datum(None, [])
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(10)],
      extra_signatories: [owner_hash],
      validity_range: interval.after(500),
    }
  !spend(d, ClosePosition, tx)
}

// ------------------------------------------------------------ CreateProposal

test create_proposal_ok() {
  let now = 500
  let p_id = proposal_token_name(pos_ref())
  let new_lock = (p_id, now + 1000, 100)
  let d = stake_datum(None, [])
  let out = pos_output(100, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(100)],
      reference_inputs: [settings_input()],
      outputs: [out],
      mint: assets.from_asset(proposal_policy, p_id, 1),
      extra_signatories: [owner_hash],
      validity_range: interval.after(now),
    }
  spend(d, CreateProposal, tx)
}

test rejects_create_below_threshold() {
  let now = 500
  let p_id = proposal_token_name(pos_ref())
  let new_lock = (p_id, now + 1000, 99)
  let d = stake_datum(None, [])
  let out = pos_output(99, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(99)],
      reference_inputs: [settings_input()],
      outputs: [out],
      mint: assets.from_asset(proposal_policy, p_id, 1),
      extra_signatories: [owner_hash],
      validity_range: interval.after(now),
    }
  !spend(d, CreateProposal, tx)
}

// ------------------------------------------------------------ CosignProposal

test cosign_proposal_ok() {
  let start = 500
  let new_lock = (prop_nft, start + 1000, 60)
  let d = stake_datum(None, [])
  let out = pos_output(60, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(60), proposal_input_draft(start)],
      reference_inputs: [settings_input()],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  spend(d, CosignProposal, tx)
}

test rejects_cosign_below_threshold() {
  let start = 500
  let new_lock = (prop_nft, start + 1000, 40)
  let d = stake_datum(None, [])
  let out = pos_output(40, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(40), proposal_input_draft(start)],
      reference_inputs: [settings_input()],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  !spend(d, CosignProposal, tx)
}

test rejects_cosign_same_proposal_twice() {
  let start = 500
  // datum already holds a lock referencing this proposal
  let existing = (prop_nft, start + 1000, 60)
  let new_lock = (prop_nft, start + 1000, 60)
  let d = stake_datum(None, [existing])
  let out = pos_output(60, stake_datum(None, [existing, new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(60), proposal_input_draft(start)],
      reference_inputs: [settings_input()],
      outputs: [out],
      extra_signatories: [owner_hash],
    }
  !spend(d, CosignProposal, tx)
}

// -------------------------------------------------------------- VoteProposal

test vote_proposal_ok() {
  let start = 500
  let unlock = start + 1000 + 2000 + 3000
  let new_lock = (prop_nft, unlock, 20)
  let d = stake_datum(None, [])
  let out = pos_output(20, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(20)],
      reference_inputs: [settings_input(), proposal_ref_voting(start)],
      outputs: [out],
      mint: assets.from_asset(vote_policy, "V", 1),
      extra_signatories: [owner_hash],
    }
  spend(d, VoteProposal, tx)
}

test rejects_vote_when_not_voting_stage() {
  let start = 500
  let unlock = start + 1000 + 2000 + 3000
  let new_lock = (prop_nft, unlock, 20)
  let d = stake_datum(None, [])
  let out = pos_output(20, stake_datum(None, [new_lock]))
  let tx =
    Transaction {
      ..placeholder,
      inputs: [pos_input(20)],
      reference_inputs: [settings_input(), proposal_input_draft(start)],
      outputs: [out],
      mint: assets.from_asset(vote_policy, "V", 1),
      extra_signatories: [owner_hash],
    }
  !spend(d, VoteProposal, tx)
}

// ------------------------------------------------------ position NFT minting

test create_position_ok() {
  let seed = OutputReference { transaction_id: tx_id, output_index: 7 }
  let name = nft_name_from_ref(seed)
  let seed_input =
    Input {
      output_reference: seed,
      output: Output {
        address: from_script(gov_policy),
        value: assets.from_lovelace(2_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let position =
    Output {
      address: from_script(stake_hash),
      value: assets.from_asset(stake_hash, name, 1),
      datum: InlineDatum(stake_datum(None, [])),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..placeholder,
      inputs: [seed_input],
      outputs: [position],
      mint: assets.from_asset(stake_hash, name, 1),
    }
  validate_create_position(stake_hash, tx)
}

test rejects_create_position_with_locks() {
  let seed = OutputReference { transaction_id: tx_id, output_index: 7 }
  let name = nft_name_from_ref(seed)
  let seed_input =
    Input {
      output_reference: seed,
      output: Output {
        address: from_script(gov_policy),
        value: assets.from_lovelace(2_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let position =
    Output {
      address: from_script(stake_hash),
      value: assets.from_asset(stake_hash, name, 1),
      datum: InlineDatum(stake_datum(None, [(prop_nft, 1, 1)])),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..placeholder,
      inputs: [seed_input],
      outputs: [position],
      mint: assets.from_asset(stake_hash, name, 1),
    }
  !validate_create_position(stake_hash, tx)
}

test close_position_mint_ok() {
  let tx =
    Transaction {
      ..placeholder,
      mint: assets.from_asset(stake_hash, pos_nft, -1),
    }
  validate_close_position(stake_hash, tx)
}

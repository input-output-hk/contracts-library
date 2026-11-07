use aiken/collection/dict
use cardano/address.{
  Script, VerificationKey, from_script, from_verification_key,
}
use cardano/assets
use cardano/certificate.{
  DelegateBlockProduction, DelegateCredential, RegisterCredential,
}
use cardano/governance.{
  DelegateRepresentative, NicePoll, ProposalProcedure, StakePool,
}
use cardano/script_context.{
  Minting, Proposing, Publishing, ScriptContext, ScriptInfo, Voting, Withdrawing,
}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use settings/types.{SettingsDatum}
use upgradeability/counter.{CounterDatum, state_token_name}
use upgradeability/counter_forwarder
use upgradeability/counter_logic

// ------------------------------------------------------------------- fixtures

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const settings_policy =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const settings_name = "settings"

const forwarder_hash =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const logic_hash = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const pool = #"44444444444444444444444444444444444444444444444444444444"

const vkh = #"11111111111111111111111111111111111111111111111111111111"

fn ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn settings_ref() -> Input {
  let registry: Data = dict.from_pairs([Pair(forwarder_hash, logic_hash)])
  Input {
    output_reference: ref(99),
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_lovelace(2_000_000)
        |> assets.add(settings_policy, settings_name, 1),
      datum: InlineDatum(
        SettingsDatum { current: registry, next: None, next_apply: None },
      ),
      reference_script: None,
    },
  }
}

fn counter_output(
  value: assets.Value,
  count: Int,
  prev_input: Option<OutputReference>,
) -> Output {
  Output {
    address: from_script(forwarder_hash),
    value,
    datum: InlineDatum(
      CounterDatum { count, owner: VerificationKey(vkh), prev_input },
    ),
    reference_script: None,
  }
}

fn with_logic(tx: Transaction) -> Transaction {
  Transaction {
    ..tx,
    reference_inputs: [settings_ref()],
    withdrawals: [Pair(Script(logic_hash), 0)],
  }
}

fn forward(info: ScriptInfo, tx: Transaction) -> Bool {
  let redeemer: Data = 0
  counter_forwarder.counter_forwarder.else(
    settings_policy,
    settings_name,
    ScriptContext { transaction: tx, redeemer, info },
  )
}

fn run_logic(tx: Transaction) -> Bool {
  let redeemer: Data = 0
  counter_logic.counter_logic.withdraw(
    settings_policy,
    settings_name,
    redeemer,
    Script(logic_hash),
    tx,
  )
}

// -------------------------------------------- the forwarder, beyond spending

test forwarder_forwards_mint() {
  forward(Minting(forwarder_hash), with_logic(placeholder))
}

test forwarder_forwards_withdraw() {
  forward(Withdrawing(Script(forwarder_hash)), with_logic(placeholder))
}

test forwarder_forwards_publish() {
  forward(
    Publishing {
      at: 0,
      certificate: DelegateCredential {
        credential: Script(forwarder_hash),
        delegate: DelegateBlockProduction(pool),
      },
    },
    with_logic(placeholder),
  )
}

test forwarder_forwards_vote() {
  forward(
    Voting(DelegateRepresentative(Script(forwarder_hash))),
    with_logic(placeholder),
  )
}

// ------------------------------------------------------- counterfeit counters

test logic_rejects_a_counterfeit_counter() fail {
  let forged = Input {
    output_reference: ref(0),
    output: counter_output(assets.from_lovelace(2_000_000), 999, None),
  }
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [forged],
        outputs: [
          counter_output(assets.from_lovelace(2_000_000), 1000, Some(ref(0))),
        ],
      },
    ),
  )
}

test forwarder_rejects_mint_without_logic() fail {
  forward(
    Minting(forwarder_hash),
    Transaction { ..placeholder, reference_inputs: [settings_ref()] },
  )
}

test forwarder_rejects_withdraw_from_another_credential() fail {
  forward(Withdrawing(VerificationKey(vkh)), with_logic(placeholder))
}

// ------------------------------------------------------------ the state token

const state_name = state_token_name

fn state_token() -> assets.Value {
  assets.from_lovelace(2_000_000)
    |> assets.add(forwarder_hash, state_name, 1)
}

fn genuine_counter(index: Int, count: Int) -> Input {
  Input {
    output_reference: ref(index),
    output: counter_output(state_token(), count, None),
  }
}

test logic_rejects_a_free_mint_alongside_a_tick() fail {
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [genuine_counter(0, 5)],
        outputs: [counter_output(state_token(), 6, Some(ref(0)))],
        mint: assets.from_asset(forwarder_hash, state_name, 1000),
      },
    ),
  )
}

// ------------------------------------------------------------ positive paths

test logic_ticks_a_genuine_counter() {
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [genuine_counter(0, 5)],
        outputs: [counter_output(state_token(), 6, Some(ref(0)))],
      },
    ),
  )
}

fn genesis(minted: assets.Value, output: Output) -> Bool {
  run_logic(
    with_logic(Transaction { ..placeholder, outputs: [output], mint: minted }),
  )
}

test logic_accepts_a_genesis_mint() {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    counter_output(state_token(), 0, None),
  )
}

test logic_rejects_a_genesis_with_a_nonzero_count() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    counter_output(state_token(), 7, None),
  )
}

test logic_rejects_a_genesis_tagged_as_a_continuation() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    counter_output(state_token(), 0, Some(ref(3))),
  )
}

test logic_rejects_a_mint_that_leaves_the_forwarder() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    Output {
      ..counter_output(state_token(), 0, None),
      address: from_script(pool),
    },
  )
}

test logic_rejects_minting_two_tokens() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 2),
    counter_output(
      assets.add(state_token(), forwarder_hash, state_name, 1),
      0,
      None,
    ),
  )
}

test logic_rejects_another_asset_name() fail {
  genesis(
    assets.from_asset(forwarder_hash, "other", 1),
    counter_output(
      assets.from_lovelace(2_000_000) |> assets.add(forwarder_hash, "other", 1),
      0,
      None,
    ),
  )
}

test logic_rejects_a_burn() fail {
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [genuine_counter(0, 5)],
        outputs: [],
        mint: assets.from_asset(forwarder_hash, state_name, -1),
      },
    ),
  )
}

test logic_rejects_a_genesis_with_a_reference_script() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    Output {
      ..counter_output(state_token(), 0, None),
      reference_script: Some(forwarder_hash),
    },
  )
}

test logic_rejects_a_genesis_without_an_inline_datum() fail {
  genesis(
    assets.from_asset(forwarder_hash, state_name, 1),
    Output { ..counter_output(state_token(), 0, None), datum: DatumHash(tx_id) },
  )
}

/// The fresh counter needs `prev_input: None`, so the tick's continuation
/// cannot stand in for it.
test logic_accepts_a_genesis_alongside_a_tick() {
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [genuine_counter(0, 5)],
        outputs: [
          counter_output(state_token(), 6, Some(ref(0))),
          counter_output(state_token(), 0, None),
        ],
        mint: assets.from_asset(forwarder_hash, state_name, 1),
      },
    ),
  )
}

/// A valid tick plus a mint whose token goes to a wallet: only the tick's
/// continuation is at the forwarder, and it is not a fresh counter.
test logic_rejects_a_genesis_whose_token_leaves_alongside_a_tick() fail {
  run_logic(
    with_logic(
      Transaction {
        ..placeholder,
        inputs: [genuine_counter(0, 5)],
        outputs: [
          counter_output(state_token(), 6, Some(ref(0))),
          Output {
            address: from_verification_key(vkh),
            value: state_token(),
            datum: NoDatum,
            reference_script: None,
          },
        ],
        mint: assets.from_asset(forwarder_hash, state_name, 1),
      },
    ),
  )
}

// ---------------------------------------- unhandled purposes, reject by default

fn tick_with(extra: fn(Transaction) -> Transaction) -> Bool {
  run_logic(
    extra(
      with_logic(
        Transaction {
          ..placeholder,
          inputs: [genuine_counter(0, 5)],
          outputs: [counter_output(state_token(), 6, Some(ref(0)))],
        },
      ),
    ),
  )
}

test logic_rejects_a_delegated_withdrawal() fail {
  tick_with(
    fn(tx) {
      Transaction {
        ..tx,
        withdrawals: [
          Pair(Script(forwarder_hash), 1_000_000),
          Pair(Script(logic_hash), 0),
        ],
      }
    },
  )
}

test logic_rejects_a_delegated_certificate() fail {
  tick_with(
    fn(tx) {
      Transaction {
        ..tx,
        certificates: [
          DelegateCredential {
            credential: Script(forwarder_hash),
            delegate: DelegateBlockProduction(pool),
          },
        ],
      }
    },
  )
}

test logic_rejects_a_delegated_vote() fail {
  tick_with(
    fn(tx) {
      Transaction {
        ..tx,
        votes: [Pair(DelegateRepresentative(Script(forwarder_hash)), [])],
      }
    },
  )
}

test logic_ignores_unrelated_certificates() {
  tick_with(
    fn(tx) {
      Transaction {
        ..tx,
        certificates: [
          RegisterCredential {
            credential: VerificationKey(vkh),
            deposit: Never,
          },
        ],
      }
    },
  )
}

test logic_rejects_when_nothing_is_delegated() fail {
  run_logic(with_logic(placeholder))
}

test forwarder_rejects_a_stake_pool_voter() fail {
  forward(Voting(StakePool(vkh)), with_logic(placeholder))
}

test forwarder_rejects_a_proposal() fail {
  forward(
    Proposing {
      at: 0,
      proposal_procedure: ProposalProcedure {
        deposit: 0,
        return_address: Script(forwarder_hash),
        governance_action: NicePoll,
      },
    },
    with_logic(placeholder),
  )
}

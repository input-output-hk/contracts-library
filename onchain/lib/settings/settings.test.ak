use aiken/builtin.{constr_data, i_data}
use aiken/interval
use cardano/address.{VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use settings/reference.{reference_mint, reference_spend}
use settings/typed.{validate_datum}
use settings/types.{
  Apply, Burn, Close, Mint, Propose, SettingsDatum, SpendRedeemer,
}
use settings/utils.{get_settings_datum}

// ----------------------------------------------------------------- fixtures

const policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const token = "settings"

const other_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const proposer = #"11111111111111111111111111111111111111111111111111111111"

const applier = #"22222222222222222222222222222222222222222222222222222222"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

/// `apply_delay` (ms) and the `now` (validity lower bound) used by the fixtures.
const delay = 1000

const now = 1500

fn value_a() -> Data {
  constr_data(0, [i_data(42)])
}

fn value_b() -> Data {
  constr_data(0, [i_data(7)])
}

fn value_nft() -> assets.Value {
  assets.from_lovelace(2_000_000) |> assets.add(policy, token, 1)
}

fn datum(current: Data) -> SettingsDatum {
  SettingsDatum { current, next: None, next_apply: None }
}

fn seed_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn seed_input() -> Input {
  Input {
    output_reference: seed_ref(),
    output: Output {
      address: from_script(other_policy),
      value: assets.from_lovelace(1),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn settings_in(d: SettingsDatum) -> Input {
  Input { output_reference: seed_ref(), output: settings_out(d, value_nft()) }
}

fn settings_out(d: SettingsDatum, value: assets.Value) -> Output {
  Output {
    address: from_script(policy),
    value,
    datum: InlineDatum(d),
    reference_script: None,
  }
}

fn spend_tx(
  inputs: List<Input>,
  outputs: List<Output>,
  at: Int,
  signers: List<ByteArray>,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs,
    outputs,
    validity_range: interval.after(at),
    extra_signatories: signers,
  }
}

fn spend_on_tx(
  redeemer: SpendRedeemer,
  input_datum: SettingsDatum,
  tx: Transaction,
) -> Bool {
  reference_spend(
    VerificationKey(proposer),
    VerificationKey(applier),
    delay,
    token,
    Some(input_datum),
    redeemer,
    seed_ref(),
    tx,
    validate_datum,
  )
}

fn spend(
  redeemer: SpendRedeemer,
  input_datum: SettingsDatum,
  output_datum: SettingsDatum,
  at: Int,
  signers: List<ByteArray>,
) -> Bool {
  spend_on_tx(
    redeemer,
    input_datum,
    spend_tx(
      [settings_in(input_datum)],
      [settings_out(output_datum, value_nft())],
      at,
      signers,
    ),
  )
}

fn proposed_with(next_value: Data, at: Int) -> SettingsDatum {
  SettingsDatum {
    current: value_a(),
    next: Some(next_value),
    next_apply: Some(at),
  }
}

fn pending() -> SettingsDatum {
  proposed_with(value_b(), now)
}

fn proposed() -> SettingsDatum {
  proposed_with(value_b(), now + delay)
}

fn mint_tx() -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [seed_input()],
    outputs: [settings_out(datum(value_a()), value_nft())],
    mint: assets.from_asset(policy, token, 1),
    extra_signatories: [applier],
  }
}

fn launch(tx: Transaction) -> Bool {
  reference_mint(
    seed_ref(),
    VerificationKey(applier),
    token,
    Mint { out_ix: 0 },
    policy,
    tx,
    validate_datum,
  )
}

fn burn(tx: Transaction) -> Bool {
  reference_mint(
    seed_ref(),
    VerificationKey(applier),
    token,
    Burn,
    policy,
    tx,
    validate_datum,
  )
}

fn reference_input() -> Input {
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 1 },
    output: settings_out(datum(value_a()), value_nft()),
  }
}

// ------------------------------------------------------------ launch / burn

test mint_ok() {
  launch(mint_tx())
}

test rejects_action_by_wrong_credential() {
  // Propose needs `propose_auth`; launch/apply/close need `apply_auth`.
  !spend(Propose { out_ix: 0 }, datum(value_a()), proposed(), now, [applier]) && !spend(
    Apply { out_ix: 0 },
    pending(),
    datum(value_b()),
    now,
    [proposer],
  ) && !launch(Transaction { ..mint_tx(), extra_signatories: [proposer] }) && !spend_on_tx(
    Close,
    datum(value_a()),
    Transaction {
      ..spend_tx([settings_in(datum(value_a()))], [], now, [proposer]),
      mint: assets.from_asset(policy, token, -1),
    },
  )
}

test rejects_mint_bad_state() {
  let tx = mint_tx()
  !launch(Transaction { ..tx, mint: assets.from_asset(policy, "X", 1) }) && !launch(
    Transaction { ..tx, mint: assets.from_asset(policy, token, 2) },
  ) && !launch(
    Transaction {
      ..tx,
      outputs: [settings_out(proposed_with(value_b(), now), value_nft())],
    },
  ) && !launch(
    Transaction {
      ..tx,
      outputs: [
        settings_out(
          SettingsDatum {
            current: value_a(),
            next: None,
            next_apply: Some(now),
          },
          value_nft(),
        ),
      ],
    },
  ) && !launch(
    Transaction {
      ..tx,
      outputs: [settings_out(datum(constr_data(1, [value_a()])), value_nft())],
    },
  )
}

test rejects_mint_wrong_output() {
  let out = settings_out(datum(value_a()), value_nft())
  !launch(
    Transaction {
      ..mint_tx(),
      outputs: [Output { ..out, address: from_script(other_policy) }],
    },
  ) && !launch(
    Transaction {
      ..mint_tx(),
      outputs: [Output { ..out, value: assets.from_lovelace(2_000_000) }],
    },
  ) && !launch(
    Transaction {
      ..mint_tx(),
      outputs: [
        Output { ..out, value: value_nft() |> assets.add(other_policy, "X", 1) },
      ],
    },
  )
}

test rejects_mint_non_inline_datum() fail {
  launch(
    Transaction {
      ..mint_tx(),
      outputs: [
        Output {
          ..settings_out(datum(value_a()), value_nft()),
          datum: DatumHash(tx_id),
        },
      ],
    },
  )
}

test rejects_mint_missing_seed() fail {
  launch(Transaction { ..mint_tx(), inputs: [] })
}

test burn_ok_rejects_not_minus_one() {
  burn(
    Transaction { ..placeholder, mint: assets.from_asset(policy, token, -1) },
  ) && !burn(
    Transaction { ..placeholder, mint: assets.from_asset(policy, token, -2) },
  ) && !burn(
    Transaction { ..placeholder, mint: assets.from_asset(policy, token, 1) },
  )
}

// --------------------------------------------------------- typed predicate

test typed_predicate_accepts_and_rejects_wrong_shape() {
  validate_datum(constr_data(0, [i_data(42)])) && validate_datum(
    constr_data(0, [constr_data(1, [i_data(42)])]),
  ) && !validate_datum(constr_data(1, [i_data(42)])) && !validate_datum(
    constr_data(0, []),
  ) && !validate_datum(constr_data(0, [i_data(42), i_data(43)]))
}

test rejects_non_constructor_value() fail {
  validate_datum(i_data(42))
}

// ---------------------------------------------------------------- propose

test propose_ok() {
  spend(Propose { out_ix: 0 }, datum(value_a()), proposed(), now, [proposer])
}

test rejects_propose_tampering() {
  !spend(
    Propose { out_ix: 0 },
    datum(value_a()),
    SettingsDatum {
      current: value_b(),
      next: Some(value_b()),
      next_apply: Some(now + delay),
    },
    now,
    [proposer],
  ) && !spend(
    Propose { out_ix: 0 },
    datum(value_a()),
    proposed_with(value_a(), now + delay),
    now,
    [proposer],
  ) && !spend(
    Propose { out_ix: 0 },
    datum(value_a()),
    proposed_with(value_b(), now + delay - 1),
    now,
    [proposer],
  )
}

test propose_longer_than_required_delay_is_accepted() {
  // The validator enforces a minimum delay (`next_apply >= now + apply_delay`,
  // spec §5.b), so a proposer may choose a later apply time.
  spend(
    Propose { out_ix: 0 },
    datum(value_a()),
    proposed_with(value_b(), now + delay + 1),
    now,
    [proposer],
  )
}

test rejects_propose_unbounded_range() fail {
  let d = datum(value_a())
  spend_on_tx(
    Propose { out_ix: 0 },
    d,
    Transaction {
      ..placeholder,
      inputs: [settings_in(d)],
      outputs: [settings_out(proposed(), value_nft())],
      extra_signatories: [proposer],
    },
  )
}

test rejects_propose_nft_detached() fail {
  let d = datum(value_a())
  spend_on_tx(
    Propose { out_ix: 0 },
    d,
    spend_tx(
      [settings_in(d)],
      [settings_out(proposed(), assets.from_lovelace(2_000_000))],
      now,
      [proposer],
    ),
  )
}

// ------------------------------------------------------------------ apply

test apply_ok_at_deadline_boundary() {
  spend(Apply { out_ix: 0 }, pending(), datum(value_b()), now, [applier])
}

test rejects_apply_premature_or_tampered() {
  !spend(Apply { out_ix: 0 }, pending(), datum(value_b()), now - 1, [applier]) && !spend(
    Apply { out_ix: 0 },
    pending(),
    datum(value_a()),
    now,
    [applier],
  )
}

test rejects_apply_without_pending() fail {
  spend(Apply { out_ix: 0 }, datum(value_a()), datum(value_a()), now, [applier])
}

// ------------------------------------------------------------------ close

test close_ok() {
  spend_on_tx(
    Close,
    datum(value_a()),
    Transaction {
      ..spend_tx([settings_in(datum(value_a()))], [], now, [applier]),
      mint: assets.from_asset(policy, token, -1),
    },
  )
}

test rejects_close_without_burn() fail {
  spend_on_tx(
    Close,
    datum(value_a()),
    spend_tx([settings_in(datum(value_a()))], [], now, [applier]),
  )
}

// ------------------------------------------------------------------ utils

test get_settings_datum_reads_reference_input() {
  let tx = Transaction {
    ..placeholder,
    reference_inputs: [seed_input(), reference_input()],
  }
  let settings = get_settings_datum(tx, policy, token)
  settings.current == value_a() && settings.next == None && settings.next_apply == None
}

test rejects_get_settings_datum_without_reference() fail {
  let settings = get_settings_datum(placeholder, policy, token)
  settings.current == value_a()
}

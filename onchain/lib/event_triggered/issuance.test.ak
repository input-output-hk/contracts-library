// Minimum flow tests for the issuance logic (spec §4.1 RegisterAndMint,
// §4.5 Burn). Fixture style mirrors `lib/dao/proposal/proposal.test.ak`.

use aiken/interval
use cardano/address.{
  Address, Credential, Script, VerificationKey, from_script,
  from_verification_key, with_delegation_key, with_delegation_script,
}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/issuance
use event_triggered/types.{
  BondExtra, Burn, MintingAction, MintingParams, PrincipalDatum, ReferenceDatum,
  RegisterAndMint, RegistryNode, ScheduleStep,
}

// ------------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const node_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const native_policy =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const plb_script = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const minting_script =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const transfer_script =
  #"11111111111111111111111111111111111111111111111111111111"

const third_party_script =
  #"22222222222222222222222222222222222222222222222222222222"

const tscript_hash = #"33333333333333333333333333333333333333333333333333333333"

const issuer_key = #"44444444444444444444444444444444444444444444444444444444"

const owner1_key = #"55555555555555555555555555555555555555555555555555555555"

const owner2_key = #"66666666666666666666666666666666666666666666666666666666"

const payment1_key = #"77777777777777777777777777777777777777777777777777777777"

const principal_name = "BOND"

const ref_name = "REF"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn schedule() -> List<ScheduleStep> {
  [
    ScheduleStep { deadline: 1000, value: 1040 },
    ScheduleStep { deadline: 2000, value: 1081 },
    ScheduleStep { deadline: 3000, value: 1124 },
    ScheduleStep { deadline: 4000, value: 1169 },
  ]
}

fn minting_params() -> MintingParams {
  MintingParams {
    registry_node_cs: node_policy,
    issuer: VerificationKey(issuer_key),
    transfer_logic: transfer_script,
    third_party_logic: third_party_script,
    transformation_script: tscript_hash,
    principal_name,
    reference_name: ref_name,
    schedule: schedule(),
    scale: 1000,
  }
}

fn account() -> Credential {
  Script(minting_script)
}

fn node_datum() -> RegistryNode {
  RegistryNode {
    key: cip_policy,
    next: cip_policy,
    minting_logic_script: Script(minting_script),
    transfer_logic_script: Script(transfer_script),
    third_party_logic_script: Script(third_party_script),
    unfracking_logic_script: VerificationKey(#""),
    global_state_cs: #"",
  }
}

fn ref_datum(value: Int) -> ReferenceDatum {
  ReferenceDatum {
    metadata: #"",
    version: 1,
    extra: BondExtra { schedule: schedule(), value, native_policy },
  }
}

fn plb_holder(key: ByteArray) -> Address {
  from_script(plb_script) |> with_delegation_key(key)
}

fn plb_script_addr() -> Address {
  from_script(plb_script) |> with_delegation_script(tscript_hash)
}

fn principal_value(qty: Int) -> assets.Value {
  assets.from_asset(cip_policy, principal_name, qty)
    |> assets.merge(assets.from_lovelace(2_000_000))
}

fn principal_holder_input(index: Int, key: ByteArray, qty: Int) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: plb_holder(key),
      value: principal_value(qty),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn principal_committed_input(
  index: Int,
  key: ByteArray,
  qty: Int,
  payment: Credential,
) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: plb_holder(key),
      value: principal_value(qty),
      datum: InlineDatum(PrincipalDatum { payment_credential: Some(payment) }),
      reference_script: None,
    },
  }
}

fn principal_output(key: ByteArray, qty: Int) -> Output {
  Output {
    address: plb_holder(key),
    value: principal_value(qty),
    datum: NoDatum,
    reference_script: None,
  }
}

fn ref_output(value: Int) -> Output {
  Output {
    address: plb_script_addr(),
    value: assets.from_asset(cip_policy, ref_name, 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(ref_datum(value)),
    reference_script: None,
  }
}

fn native_output(
  payment_key: ByteArray,
  stake_key: ByteArray,
  qty: Int,
) -> Output {
  Output {
    address: from_verification_key(payment_key)
      |> with_delegation_key(stake_key),
    value: assets.from_asset(native_policy, principal_name, qty)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: NoDatum,
    reference_script: None,
  }
}

fn node_output() -> Output {
  Output {
    address: from_script(node_policy),
    value: assets.from_asset(node_policy, cip_policy, 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
    datum: InlineDatum(node_datum()),
    reference_script: None,
  }
}

fn as_reference(index: Int, output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output,
  }
}

fn node_reference() -> Input {
  as_reference(90, node_output())
}

fn ref_reference() -> Input {
  as_reference(91, ref_output(1000))
}

fn register_mint(principal_qty: Int) -> assets.Value {
  assets.from_asset(node_policy, cip_policy, 1)
    |> assets.merge(
        assets.from_asset(cip_policy, principal_name, principal_qty),
      )
    |> assets.merge(assets.from_asset(cip_policy, ref_name, 1))
}

fn register_mint_without_node(principal_qty: Int) -> assets.Value {
  assets.from_asset(cip_policy, principal_name, principal_qty)
    |> assets.merge(assets.from_asset(cip_policy, ref_name, 1))
}

fn burn_mint(burned: Int, native_qty: Int) -> assets.Value {
  assets.from_asset(cip_policy, principal_name, burned)
    |> assets.merge(
        assets.from_asset(native_policy, principal_name, native_qty),
      )
}

fn check(action: MintingAction, self: Transaction) -> Bool {
  issuance.validate(action, account(), self, minting_params())
}

// ------------------------------------------------------ RegisterAndMint (T0/T1)

fn register_tx(principal_qty: Int) -> Transaction {
  Transaction {
    ..placeholder,
    outputs: [
      node_output(),
      principal_output(owner1_key, principal_qty),
      ref_output(1000),
    ],
    mint: register_mint(principal_qty),
    extra_signatories: [issuer_key],
    validity_range: interval.everything,
  }
}

test register_and_issue_ok() {
  check(RegisterAndMint, register_tx(1000))
}

test rejects_registration_without_issuer_signature() {
  !check(
    RegisterAndMint,
    Transaction { ..register_tx(1000), extra_signatories: [] },
  )
}

test rejects_reference_datum_tampering() {
  // the recorded value must mirror the baked schedule at par (v0 = scale)
  let bad = Output { ..ref_output(1000), datum: InlineDatum(ref_datum(9999)) }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [node_output(), principal_output(owner1_key, 1000), bad],
    },
  )
}

// ---------------------------------------------------------------- Burn (T4)

fn owner_graduation_tx(now: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [principal_holder_input(0, owner1_key, 1000)],
    reference_inputs: [node_reference(), ref_reference()],
    mint: burn_mint(-1000, 1169),
    outputs: [native_output(owner1_key, owner1_key, 1169)],
    extra_signatories: [owner1_key],
    validity_range: interval.after(now),
  }
}

fn third_party_graduation_tx(now: Int) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [
      principal_committed_input(
        0,
        owner1_key,
        1000,
        VerificationKey(payment1_key),
      ),
    ],
    reference_inputs: [node_reference(), ref_reference()],
    mint: burn_mint(-1000, 1169),
    outputs: [native_output(payment1_key, owner1_key, 1169)],
    extra_signatories: [],
    validity_range: interval.after(now),
  }
}

test graduate_owner_path_ok() {
  check(Burn, owner_graduation_tx(4000))
}

test graduate_third_party_ok() {
  check(Burn, third_party_graduation_tx(4000))
}

test rejects_graduation_before_d4() {
  !check(Burn, owner_graduation_tx(3999))
}

test rejects_graduation_without_referenced_node() fail {
  // the policy id resolves from the referenced registry node
  !check(
    Burn,
    Transaction { ..owner_graduation_tx(4000), reference_inputs: [] },
  )
}

test rejects_partial_burn() {
  // whole holdings burn: the input holds 1000 but only 500 burns
  !check(
    Burn,
    Transaction { ..owner_graduation_tx(4000), mint: burn_mint(-500, 584) },
  )
}

test rejects_native_over_mint() {
  // the native mirror is exactly burned × v4 / scale
  !check(
    Burn,
    Transaction { ..owner_graduation_tx(4000), mint: burn_mint(-1000, 1170) },
  )
}

test rejects_third_party_payout_redirect() {
  // unsigned owner, but the payout lands at a payment credential the owner
  // never committed (Q-GRAD-2: no fallback)
  let redirected = native_output(issuer_key, owner1_key, 1169)
  !check(
    Burn,
    Transaction { ..third_party_graduation_tx(4000), outputs: [redirected] },
  )
}

test rejects_third_party_unopted_token() {
  // no committed payment credential in the datum, and no owner signature
  !check(
    Burn,
    Transaction {
      ..third_party_graduation_tx(4000),
      inputs: [principal_holder_input(0, owner1_key, 1000)],
    },
  )
}

test rejects_companion_burn() fail {
  // burning the reference name alongside the principal fails closed (I8)
  check(
    Burn,
    Transaction {
      ..owner_graduation_tx(4000),
      mint: burn_mint(-1000, 1169)
        |> assets.merge(assets.from_asset(cip_policy, ref_name, -1)),
    },
  )
}

// -------------------------------------------- RegisterAndMint shape / stance

test rejects_node_nft_not_minted() {
  // the first batch mints, but no registry node NFT → the node is not created
  !check(
    RegisterAndMint,
    Transaction { ..register_tx(1000), mint: register_mint_without_node(1000) },
  )
}

test rejects_unpinned_transfer_logic() {
  let bad = Output {
    ..node_output(),
    datum: InlineDatum(
      RegistryNode {
        ..node_datum(),
        transfer_logic_script: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
      },
    ),
  }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [bad, principal_output(owner1_key, 1000), ref_output(1000)],
    },
  )
}

test rejects_unpinned_unfracking() {
  let bad = Output {
    ..node_output(),
    datum: InlineDatum(
      RegistryNode {
        ..node_datum(),
        unfracking_logic_script: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
      },
    ),
  }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [bad, principal_output(owner1_key, 1000), ref_output(1000)],
    },
  )
}

test rejects_unpinned_global_state() {
  let bad = Output {
    ..node_output(),
    datum: InlineDatum(RegistryNode { ..node_datum(), global_state_cs: #"00" }),
  }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [bad, principal_output(owner1_key, 1000), ref_output(1000)],
    },
  )
}

test rejects_first_batch_extra_name() {
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      mint: register_mint(1000)
        |> assets.merge(assets.from_asset(cip_policy, "EXTRA", 1)),
    },
  )
}

test rejects_wrong_reference_name() {
  let bad = Output {
    ..ref_output(1000),
    value: assets.from_asset(cip_policy, "OTHER", 1)
      |> assets.merge(assets.from_lovelace(2_000_000)),
  }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [node_output(), principal_output(owner1_key, 1000), bad],
    },
  )
}

test rejects_reference_not_staked() {
  let bad = Output { ..ref_output(1000), address: plb_holder(owner1_key) }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [node_output(), principal_output(owner1_key, 1000), bad],
    },
  )
}

test rejects_principal_script_staked() {
  let bad = Output {
    ..principal_output(owner1_key, 1000),
    address: plb_script_addr(),
  }
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [node_output(), bad, ref_output(1000)],
    },
  )
}

test rejects_no_node_output() fail {
  // no registry node output → the governing lookup aborts
  !check(
    RegisterAndMint,
    Transaction {
      ..register_tx(1000),
      outputs: [principal_output(owner1_key, 1000), ref_output(1000)],
    },
  )
}

// ------------------------------------------------ Burn: attribution / I7 / I8

fn two_owner_graduation_tx() -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [
      principal_holder_input(0, owner1_key, 1000),
      principal_holder_input(1, owner2_key, 1000),
    ],
    reference_inputs: [node_reference(), ref_reference()],
    mint: burn_mint(-2000, 2338),
    outputs: [
      native_output(owner1_key, owner1_key, 1169),
      native_output(owner2_key, owner2_key, 1169),
    ],
    extra_signatories: [owner1_key, owner2_key],
    validity_range: interval.after(4000),
  }
}

test multi_owner_batch_ok() {
  check(Burn, two_owner_graduation_tx())
}

test rejects_underpaid_owner() {
  // both owners' shares land at owner1's stake; each payout must be exact
  let merged = native_output(owner1_key, owner1_key, 2338)
  !check(Burn, Transaction { ..two_owner_graduation_tx(), outputs: [merged] })
}

test rejects_native_at_non_owner_stake() {
  let stray = native_output(issuer_key, issuer_key, 1169)
  !check(Burn, Transaction { ..owner_graduation_tx(4000), outputs: [stray] })
}

test rejects_registry_node_spent() {
  // I7 re-check: a registry node spend never co-occurs with issuance
  !check(
    Burn,
    Transaction {
      ..owner_graduation_tx(4000),
      inputs: [principal_holder_input(0, owner1_key, 1000), node_reference()],
    },
  )
}

test rejects_burn_of_companion_name_only() {
  !check(
    Burn,
    Transaction {
      ..owner_graduation_tx(4000),
      mint: assets.from_asset(cip_policy, ref_name, -1),
    },
  )
}

test rejects_reference_datum_missing() fail {
  // the referenced reference token must carry a decodable ReferenceDatum
  let no_datum = as_reference(91, Output { ..ref_output(1000), datum: NoDatum })
  !check(
    Burn,
    Transaction {
      ..owner_graduation_tx(4000),
      reference_inputs: [node_reference(), no_datum],
    },
  )
}

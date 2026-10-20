//// Adversarial tests for the smart wallet: each scenario runs the core wallet
//// validator and the delegated withdrawal scripts against the *same*
//// transaction, as the ledger would.
////
//// Tests marked `fail` assert that the attack transaction is rejected. Those
//// tagged `KNOWN ISSUE` are accepted by the current validators and therefore
//// fail until the corresponding fix lands; the `control_*` tests check that the
//// fixtures themselves describe valid, honest transactions.

use aiken/crypto.{ScriptHash, VerificationKeyHash}
use aiken/interval
use cardano/address.{
  Script, VerificationKey, from_script, from_verification_key,
}
use cardano/assets.{Value}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Publish, Transaction,
  placeholder,
}
use settings/types as settings_types
use smart_wallet/checks
use smart_wallet/smart_wallet
use smart_wallet/types.{
  Deposit, Mint, Spend, SpendRedeemer, UpdatePermissions, WalletConfig,
  WalletDatum,
}
use smart_wallet/withdrawal_scripts/asset_allow_list
use smart_wallet/withdrawal_scripts/asset_deposit_allow_list
use smart_wallet/withdrawal_scripts/spending_limit
use smart_wallet/withdrawal_scripts/spending_period_limit
use smart_wallet/withdrawal_scripts/spending_period_limit_logic.{
  SpendingPeriodState,
}
use smart_wallet/withdrawal_scripts/spending_window
use smart_wallet/withdrawal_scripts/spending_window_logic.{SpendingWindowState}

// ---------------------------------------------------------------- fixtures

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wallet_hash = #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

const wallet_token = "wallet"

const settings_policy =
  #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

const settings_token = "settings"

const member = #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const admin_key = #"adadadadadadadadadadadadadadadadadadadadadadadadadadadad"

const token_policy = #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"

/// Delegated script hashes.
const sw = #"51515151515151515151515151515151515151515151515151515151"

const spl = #"52525252525252525252525252525252525252525252525252525252"

const sl = #"53535353535353535353535353535353535353535353535353535353"

const adal = #"54545454545454545454545454545454545454545454545454545454"

const aal = #"55555555555555555555555555555555555555555555555555555555"

const ada = 1_000_000

const hour = 3_600_000

const day = 86_400_000

/// `spending_limit` bound and `spending_period_limit` budget.
const bound = 1_000_000

const max_spend = 10_000_000

fn seed() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 9 }
}

fn wallet_ref() -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: 0 }
}

fn nft_value(lovelace: Int) -> Value {
  assets.from_lovelace(lovelace) |> assets.add(wallet_hash, wallet_token, 1)
}

/// An output at the wallet's script address. With an NFT-less `value` it is a
/// decoy / stray output sitting at the wallet credential.
fn wallet_out(
  value: Value,
  spenders: Pairs<ScriptHash, Data>,
  depositors: Pairs<ScriptHash, Data>,
) -> Output {
  Output {
    address: from_script(wallet_hash),
    value,
    datum: InlineDatum(WalletDatum { spenders, depositors }),
    reference_script: None,
  }
}

fn wallet_in(output: Output) -> Input {
  Input { output_reference: wallet_ref(), output }
}

fn settings_input(members: List<VerificationKeyHash>, threshold: Int) -> Input {
  let config: Data = WalletConfig { members, threshold }
  Input {
    output_reference: OutputReference { transaction_id: tx_id, output_index: 7 },
    output: Output {
      address: from_script(settings_policy),
      value: assets.from_lovelace(2 * ada)
        |> assets.add(settings_policy, settings_token, 1),
      datum: InlineDatum(
        settings_types.SettingsDatum {
          current: config,
          next: None,
          next_apply: None,
        },
      ),
      reference_script: None,
    },
  }
}

fn seed_input() -> Input {
  Input {
    output_reference: seed(),
    output: Output {
      address: from_verification_key(admin_key),
      value: assets.from_lovelace(5 * ada),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// A transaction signed by the (single) member, with the 1-of-1 wallet config.
fn member_tx() -> Transaction {
  Transaction {
    ..placeholder,
    reference_inputs: [settings_input([member], 1)],
    extra_signatories: [member],
  }
}

fn admin_tx() -> Transaction {
  Transaction { ..placeholder, extra_signatories: [admin_key] }
}

fn window_state(last_upper: Int) -> Data {
  let state: Data = SpendingWindowState { last_upper }
  state
}

fn period_state(period: Int, acc_spend: Int) -> Data {
  let state: Data = SpendingPeriodState { period, acc_spend }
  state
}

fn unit() -> Data {
  let data: Data = 0
  data
}

fn register(hash: ScriptHash) -> Certificate {
  RegisterCredential { credential: Script(hash), deposit: Never }
}

fn unregister(hash: ScriptHash) -> Certificate {
  UnregisterCredential { credential: Script(hash), refund: Never }
}

// ------------------------------------------------------------- validators

fn core_spend(
  datum: WalletDatum,
  redeemer: SpendRedeemer,
  tx: Transaction,
) -> Bool {
  smart_wallet.smart_wallet.spend(
    seed(),
    settings_policy,
    settings_token,
    wallet_token,
    VerificationKey(admin_key),
    Some(datum),
    redeemer,
    wallet_ref(),
    tx,
  )
}

fn core_mint(out_ix: Int, tx: Transaction) -> Bool {
  smart_wallet.smart_wallet.mint(
    seed(),
    settings_policy,
    settings_token,
    wallet_token,
    VerificationKey(admin_key),
    Mint { out_ix },
    wallet_hash,
    tx,
  )
}

fn sw_withdraw(tx: Transaction) -> Bool {
  spending_window.spending_window.withdraw(
    Script(wallet_hash),
    wallet_token,
    hour,
    0,
    Script(sw),
    tx,
  )
}

fn spl_withdraw(tx: Transaction) -> Bool {
  spending_period_limit.spending_period_limit.withdraw(
    Script(wallet_hash),
    wallet_token,
    day,
    max_spend,
    0,
    Script(spl),
    tx,
  )
}

fn sl_withdraw(tx: Transaction) -> Bool {
  spending_limit.spending_limit.withdraw(
    Script(wallet_hash),
    wallet_token,
    bound,
    0,
    Script(sl),
    tx,
  )
}

fn sl_publish(certificate: Certificate, tx: Transaction) -> Bool {
  spending_limit.spending_limit.publish(
    Script(wallet_hash),
    wallet_token,
    bound,
    0,
    certificate,
    tx,
  )
}

fn aal_withdraw(tx: Transaction) -> Bool {
  asset_allow_list.asset_allow_list.withdraw(
    Script(wallet_hash),
    wallet_token,
    [],
    0,
    Script(aal),
    tx,
  )
}

fn adal_withdraw(tx: Transaction) -> Bool {
  asset_deposit_allow_list.asset_deposit_allow_list.withdraw(
    Script(wallet_hash),
    wallet_token,
    [],
    0,
    Script(adal),
    tx,
  )
}

// --------------------------------------------------------------- controls

test control_honest_spend_under_limit() {
  let datum = WalletDatum { spenders: [Pair(sl, unit())], depositors: [] }
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), datum.spenders, []))],
    outputs: [wallet_out(nft_value(99 * ada + 500_000), datum.spenders, [])],
    withdrawals: [Pair(Script(sl), 0)],
  }
  core_spend(datum, Spend, tx) && sl_withdraw(tx)
}

test control_honest_deposit() {
  let datum = WalletDatum { spenders: [Pair(sl, unit())], depositors: [] }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), datum.spenders, []))],
    outputs: [wallet_out(nft_value(11 * ada), datum.spenders, [])],
  }
  core_spend(datum, Deposit { out_ix: 0 }, tx)
}

test control_honest_mint() {
  let tx = Transaction {
    ..admin_tx(),
    inputs: [seed_input()],
    outputs: [wallet_out(nft_value(2 * ada), [], [])],
    mint: assets.from_asset(wallet_hash, wallet_token, 1),
  }
  core_mint(0, tx)
}

test control_honest_update_permissions() {
  let datum = WalletDatum { spenders: [], depositors: [] }
  let tx = Transaction {
    ..admin_tx(),
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), [], []))],
    outputs: [wallet_out(nft_value(10 * ada), [], [])],
  }
  core_spend(datum, UpdatePermissions { out_ix: 0 }, tx)
}

test control_honest_period_spend() {
  let current = period_state(0, 0)
  let datum = WalletDatum { spenders: [Pair(spl, current)], depositors: [] }
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), datum.spenders, []))],
    outputs: [
      wallet_out(
        nft_value(90 * ada),
        [Pair(spl, period_state(101 * day, 10 * ada))],
        [],
      ),
    ],
    withdrawals: [Pair(Script(spl), 0)],
    validity_range: interval.between(100 * day + 1_000, 100 * day + 2_000),
  }
  core_spend(datum, Spend, tx) && spl_withdraw(tx)
}

// ------------------------------------------ 1. delegated state: decoy outputs

// Fixed: the NFT-less decoy is not the wallet UTxO, so `spending_window` reads
// `last_upper = 0` from the real continuation and rejects the second spend.
test decoy_output_cannot_spoof_spending_window_state() fail {
  let datum = WalletDatum {
    spenders: [Pair(sw, window_state(0))],
    depositors: [],
  }
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), datum.spenders, []))],
    outputs: [
      wallet_out(
        assets.from_lovelace(2 * ada),
        [Pair(sw, window_state(1_000_000))],
        [],
      ),
      wallet_out(nft_value(97 * ada), [Pair(sw, window_state(0))], []),
    ],
    withdrawals: [Pair(Script(sw), 0)],
    validity_range: interval.between(1_000_000, 2_000_000),
  }
  core_spend(datum, Spend, tx) && sw_withdraw(tx)
}

// Fixed: the decoy is not the wallet UTxO, so `spending_period_limit` reads the
// real continuation's old accumulator and rejects the repeated budget.
test decoy_output_cannot_freeze_spending_period_state() fail {
  let datum = WalletDatum {
    spenders: [Pair(spl, period_state(0, 0))],
    depositors: [],
  }
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), datum.spenders, []))],
    outputs: [
      wallet_out(
        assets.from_lovelace(2 * ada),
        [Pair(spl, period_state(101 * day, 10 * ada))],
        [],
      ),
      wallet_out(nft_value(88 * ada), [Pair(spl, period_state(0, 0))], []),
    ],
    withdrawals: [Pair(Script(spl), 0)],
    validity_range: interval.between(100 * day + 1_000, 100 * day + 2_000),
  }
  core_spend(datum, Spend, tx) && spl_withdraw(tx)
}

// Fixed: the empty-spender decoy is not the wallet UTxO, so
// `own_withdrawal_removed` sees the spender still present in the real
// continuation and rejects the unregistration.
test unprivileged_deposit_cannot_unregister_spender() fail {
  let datum = WalletDatum { spenders: [Pair(sl, unit())], depositors: [] }
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), datum.spenders, []))],
    outputs: [
      wallet_out(assets.from_lovelace(2 * ada), [], []),
      wallet_out(nft_value(10 * ada), datum.spenders, []),
    ],
    certificates: [unregister(sl)],
  }
  core_spend(datum, Deposit { out_ix: 1 }, tx) && sl_publish(unregister(sl), tx)
}

// ------------------------------------------- 2. spending_window: time bounds

// Fixed: the first spend records the validity upper bound, so the second spend
// cannot backdate its lower bound into the same instant.
test spending_window_rejects_backdated_burst() fail {
  let s0 = [Pair(sw, window_state(hour))]
  let upper = 3 * hour + 1_000
  let s1 = [Pair(sw, window_state(upper))]
  let s2 = [Pair(sw, window_state(upper))]
  let tx1 = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), s0, []))],
    outputs: [wallet_out(nft_value(99 * ada), s1, [])],
    withdrawals: [Pair(Script(sw), 0)],
    validity_range: interval.between(2 * hour, upper),
  }
  let tx2 = Transaction {
    ..tx1,
    inputs: [wallet_in(wallet_out(nft_value(99 * ada), s1, []))],
    outputs: [wallet_out(nft_value(98 * ada), s2, [])],
    validity_range: interval.between(3 * hour, upper),
  }
  sw_withdraw(tx1) && sw_withdraw(tx2)
}

// ------------------------------------ 3. spending_period_limit: time bounds

// Fixed: both validity intervals span multiple periods, so neither can be
// charged to a single period and both spends are rejected.
test spending_period_limit_rejects_historical_budgets() fail {
  let s0 = [Pair(spl, period_state(0, 0))]
  let s1 = [Pair(spl, period_state(51 * day, 10 * ada))]
  let s2 = [Pair(spl, period_state(61 * day, 10 * ada))]
  let upper = 100 * day + 1_000
  let tx1 = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), s0, []))],
    outputs: [wallet_out(nft_value(90 * ada), s1, [])],
    withdrawals: [Pair(Script(spl), 0)],
    validity_range: interval.between(50 * day + 1, upper),
  }
  let tx2 = Transaction {
    ..tx1,
    inputs: [wallet_in(wallet_out(nft_value(90 * ada), s1, []))],
    outputs: [wallet_out(nft_value(80 * ada), s2, [])],
    validity_range: interval.between(60 * day + 1, upper),
  }
  spl_withdraw(tx1) && spl_withdraw(tx2)
}

// ------------------------------ 4. value accounting: stray wallet outputs

// Fixed: `spending_limit` sums only the NFT-bearing continuation, so the 98 ADA
// moved to the NFT-less output are counted as outflow; the core also rejects the
// stray output outright.
test spending_limit_counts_only_authenticated_continuation() fail {
  let datum = WalletDatum { spenders: [Pair(sl, unit())], depositors: [] }
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(wallet_out(nft_value(100 * ada), datum.spenders, []))],
    outputs: [
      wallet_out(nft_value(2 * ada), datum.spenders, []),
      wallet_out(assets.from_lovelace(98 * ada), datum.spenders, []),
    ],
    withdrawals: [Pair(Script(sl), 0)],
  }
  core_spend(datum, Spend, tx) && sl_withdraw(tx)
}

// Fixed: the asset list sums only the NFT-bearing continuation, so the token
// moved to the stray output is seen as leaving the wallet; the core also rejects
// the stray output outright.
test asset_allow_list_counts_only_authenticated_continuation() fail {
  let datum = WalletDatum { spenders: [Pair(aal, unit())], depositors: [] }
  let tx = Transaction {
    ..member_tx(),
    inputs: [
      wallet_in(
        wallet_out(
          nft_value(10 * ada) |> assets.add(token_policy, "x", 1),
          datum.spenders,
          [],
        ),
      ),
    ],
    outputs: [
      wallet_out(nft_value(8 * ada), datum.spenders, []),
      wallet_out(
        assets.from_lovelace(2 * ada) |> assets.add(token_policy, "x", 1),
        datum.spenders,
        [],
      ),
    ],
    withdrawals: [Pair(Script(aal), 0)],
  }
  core_spend(datum, Spend, tx) && aal_withdraw(tx)
}

// Passes today: the stray output from the scenarios above can never be spent
// again (no NFT), so the "retained" funds are permanently locked.
test stray_wallet_output_is_unspendable() fail {
  let datum = WalletDatum { spenders: [], depositors: [] }
  let stray = wallet_out(assets.from_lovelace(98 * ada), [], [])
  let tx = Transaction {
    ..member_tx(),
    inputs: [wallet_in(stray)],
    outputs: [wallet_out(assets.from_lovelace(98 * ada), [], [])],
  }
  core_spend(datum, Spend, tx)
}

// ----------------------------------- 5. registration proves initialization

// KNOWN ISSUE: a legacy stake registration certificate needs no script
// witness, so `publish` never runs; the wallet only looks for the certificate
// and accepts an invalid initial `spending_window` state. A sound check must
// see a matching `Publish` redeemer.
test mint_requires_publish_execution() fail {
  let tx = Transaction {
    ..admin_tx(),
    inputs: [seed_input()],
    outputs: [wallet_out(nft_value(2 * ada), [Pair(sw, window_state(500))], [])],
    mint: assets.from_asset(wallet_hash, wallet_token, 1),
    certificates: [register(sw)],
    redeemers: [],
  }
  core_mint(0, tx)
}

// ----------------------------------------- 6. UpdatePermissions keeps value

// KNOWN ISSUE: `assets.match(.., >=)` lets the admin add ADA on an update,
// bypassing the deposit scripts, while the spec says "same value".
test update_permissions_preserves_value() fail {
  let datum = WalletDatum { spenders: [], depositors: [] }
  let tx = Transaction {
    ..admin_tx(),
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), [], []))],
    outputs: [wallet_out(nft_value(12 * ada), [], [])],
  }
  core_spend(datum, UpdatePermissions { out_ix: 0 }, tx)
}

// ---------------------------------------------- configuration validity

// KNOWN ISSUE: a duplicated member counts twice toward the threshold.
test duplicate_members_count_once() fail {
  checks.members_signed([member, member], 2, [member])
}

// KNOWN ISSUE: duplicate keys in `spenders` are accepted at mint (and break
// the uniqueness `same_keys` relies on). The `Publish` redeemer is included so
// the rejection must come from the duplicate, not from finding 5.
test mint_rejects_duplicate_spender_keys() fail {
  let cert = register(sl)
  let tx = Transaction {
    ..admin_tx(),
    inputs: [seed_input()],
    outputs: [
      wallet_out(nft_value(2 * ada), [Pair(sl, unit()), Pair(sl, unit())], []),
    ],
    mint: assets.from_asset(wallet_hash, wallet_token, 1),
    certificates: [cert],
    redeemers: [Pair(Publish { at: 0, certificate: cert }, unit())],
  }
  core_mint(0, tx)
}

// KNOWN ISSUE: a stateless depositor's `Data` is not pinned, so any depositor
// (no signature) can replace it with arbitrary bytes, bloating the datum.
test deposit_cannot_rewrite_stateless_depositor_data() fail {
  let datum = WalletDatum { spenders: [], depositors: [Pair(adal, unit())] }
  let junk: Data = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  let tx = Transaction {
    ..placeholder,
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), [], datum.depositors))],
    outputs: [wallet_out(nft_value(11 * ada), [], [Pair(adal, junk)])],
    withdrawals: [Pair(Script(adal), 0)],
  }
  core_spend(datum, Deposit { out_ix: 0 }, tx) && adal_withdraw(tx)
}

// Passes today, contradicting `usage.md`: removing and re-adding a script in
// the same transaction cannot reset its state, since a hash present on both
// sides is "kept" and must carry byte-identical `Data`.
test update_cannot_reset_state_in_one_tx() fail {
  let datum = WalletDatum {
    spenders: [Pair(sw, window_state(5_000))],
    depositors: [],
  }
  let tx = Transaction {
    ..admin_tx(),
    inputs: [wallet_in(wallet_out(nft_value(10 * ada), datum.spenders, []))],
    outputs: [wallet_out(nft_value(10 * ada), [Pair(sw, window_state(0))], [])],
    certificates: [unregister(sw), register(sw)],
  }
  core_spend(datum, UpdatePermissions { out_ix: 0 }, tx)
}

// Smart Wallet — transaction design (based on docs/smart-wallet/summary.md).
// A wallet with configurable restrictions; the primary implementation of the
// pluggable-authorization interface in ARCHITECTURE.md §2/§3. Two layers:
//   - L1 forwarding credential: a spending script holds the funds and checks a
//     base M-of-N signature floor, delegating every other authorization to
//     withdraw-0 staking scripts. One spend redeemer asserts the conjunction of
//     the M-of-N floor and all delegated staking authorizations.
//   - L2 self-governing config: the list of withdrawal Credentials lives in a
//     beacon-authenticated config UTxO (the settings protocol), so it is
//     updatable without redeploying consumers.

#import "../diagrams-template.typ": *

#show: report

= Spend (base M-of-N + delegated authorizations)
_The wallet pays out. The spending script enforces its base M-of-N signature
floor and forwards every other check to the withdrawal scripts named in the
config UTxO; the single spend redeemer asserts their conjunction._

#let spend_tx = vanilla_transaction(
  "Spend",
  inputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      redeemer: [Spend],
      value: ("ada": "x"),
    ),
    (
      reference: true,
      name: "Config UTxO",
      address: "config_addr",
      value: ("Settings NFT": "1"),
      datum: (
        members: "List(Credential)",
        threshold: "Int",
        withdrawals: "List(Credential)",
      ),
    ),
  ),
  withdrawals: (
    "each credential in config.withdrawals",
  ),
  outputs: (
    (
      name: "Payout",
      wallet: true,
      value: ("ada": "y"),
    ),
    (
      name: "Wallet change (if partial)",
      address: "wallet_addr",
      value: ("ada": "x - y"),
    ),
  ),
  signatures: (
    "any m of the n members",
  ),
  notes: [
    - `wallet_addr`: payment is `wallet_hash`, staking any. Wallet UTxOs carry
      no datum; they may hold ada and arbitrary native assets.
    - `wallet_hash = hash(spend_validator(config_policy))`: the spending script
      is parameterized only by the config beacon policy, so all wallet UTxOs
      share one address and the config can change without redeploying.
    - base M-of-N floor (L1): the config UTxO is read as a *reference input*,
      and the spend requires at least `threshold` of `members` present in
      `extra_signatories`. A member may itself be a script credential, so the
      floor can be another multisig, a DAO, and so on.
    - delegated authorizations (L1): every `Credential` in `config.withdrawals`
      is a withdraw-0 staking script that must run in this transaction. The
      single spend redeemer asserts the conjunction — the M-of-N floor *and*
      all delegated checks — so no restriction can be silently omitted.
    - the delegated scripts are the extension point: spending limits, time
      locks, recipient allow-lists, oracle attestations, … each is an
      independent withdrawal script observed here, none known to the spending
      script.
    - composability: the spend asserts only its own inputs, the referenced
      config, and that the required withdrawals ran — never the total input or
      output counts, nor unrelated UTxOs.
  ],
)

#figure(spend_tx, caption: [Spend (base M-of-N + delegated authorizations)]) <fig:spend>

#pagebreak()

= Update config (self-governance)
_The wallet rewrites its own restrictions — members, threshold, or the list of
delegated withdrawal Credentials — in place. The config UTxO is the settings
protocol's beacon-authenticated UTxO, so consumers never redeploy._

#let update_config_tx = vanilla_transaction(
  "Update config",
  inputs: (
    (
      name: "Config UTxO",
      address: "config_addr",
      redeemer: [Update],
      value: ("Settings NFT": "1"),
      datum: (
        members: "List(Credential)",
        threshold: "Int",
        withdrawals: "List(Credential)",
      ),
    ),
  ),
  withdrawals: (
    "authorization credential (current config)",
  ),
  outputs: (
    (
      name: "Config UTxO",
      address: "config_addr",
      value: ("Settings NFT": "1"),
      datum: (
        members: [*members'*],
        threshold: [*m'*],
        withdrawals: [*withdrawals'*],
      ),
    ),
  ),
  notes: [
    - `config_addr` / `Settings NFT`: this is the settings protocol UTxO. Its
      lifecycle (launch, propose, apply, close) and its beacon authentication
      are defined in `docs/settings/design.typ`; this diagram only shows the
      wallet-specific datum it carries.
    - L2 (self-governing config): because the restrictions live in the
      beacon-authenticated config UTxO rather than in each consumer's
      parameters, the wallet updates its own policy without redeploying the
      spending script or any delegated withdrawal script.
    - the update is authorized by the settings protocol's configured
      credential (see the settings design). Consumers depend only on the
      config beacon policy, so a rotated member set or a new withdrawal script
      takes effect on the next spend automatically.
    - transition well-formedness: `1 <= threshold <= len(members)` and every
      entry in `withdrawals` is a valid credential — an update that could brick
      the wallet is rejected.
  ],
)

#figure(update_config_tx, caption: [Update config (self-governance)]) <fig:update-config>

// Smart Wallet — transaction design (based on docs/smart-wallet/summary.md).
// A wallet with configurable restrictions; the primary implementation of the
// pluggable-authorization interface in ARCHITECTURE.md §2/§3. A spending script
// holds the funds and checks a base M-of-N signature floor, delegating every
// other authorization to the withdraw-0 staking scripts listed in the wallet
// UTxO's own datum. One spend redeemer asserts the conjunction of the M-of-N
// floor and all delegated staking authorizations. An admin credential (a
// parameter of the spending script) may rewrite that list in place.
//
// The M-of-N members and threshold are supplied as external configuration; this
// design is agnostic of how they are sourced (a settings UTxO, script
// parameters, another on-chain config, …), so only the spend's use of that
// config is shown.

#import "../diagrams-template.typ": *

#show: report

= Spend (base M-of-N + delegated authorizations)
_The wallet pays out. The spending script enforces its base M-of-N signature
floor and forwards every other check to the withdrawal scripts named in the
wallet UTxO's datum; the single spend redeemer asserts their conjunction._

#let spend_tx = vanilla_transaction(
  "Spend",
  inputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      redeemer: [Spend],
      value: ("ada": "x"),
      datum: (
        withdrawals: "List(Credential)",
      ),
    ),
  ),
  withdrawals: (
    "each credential in the wallet datum's withdrawals",
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
      datum: (
        withdrawals: "List(Credential)",
      ),
    ),
  ),
  signatures: (
    "any m of the n members",
  ),
  notes: [
    - `wallet_addr`: payment is `wallet_hash`, staking any. Wallet UTxOs carry
      no datum; they may hold ada and arbitrary native assets.
    - `wallet_hash = hash(spend_validator(config, admin))`: the spending script
      is parameterized by its configuration reference and the `admin`
      credential, so all wallet UTxOs share one address. Externalizing the
      members/threshold config lets it change without redeploying the script.
    - base M-of-N floor: the wallet's configuration supplies `members` and
      `threshold`, and the spend requires at least `threshold` of `members`
      present in `extra_signatories`. A member may itself be a script
      credential, so the floor can be another multisig, a DAO, and so on. This
      design is agnostic of how that configuration is sourced.
    - delegated authorizations: every `Credential` in the wallet UTxO's
      `withdrawals` datum field is a withdraw-0 staking script that must run in
      this transaction. The `Spend` redeemer asserts the conjunction — the
      M-of-N floor *and* all delegated checks — so no restriction can be
      silently omitted. The list is per-UTxO, so different wallet UTxOs may
      carry different restriction sets.
    - the delegated scripts are the extension point: spending limits, time
      locks, recipient allow-lists, oracle attestations, … each is an
      independent withdrawal script observed here, none known to the spending
      script.
    - composability: the spend asserts only its own inputs and that the
      required withdrawals ran — never the total input or output counts, nor
      unrelated UTxOs.
  ],
)

#figure(spend_tx, caption: [Spend (base M-of-N + delegated authorizations)]) <fig:spend>

#pagebreak()

= Update withdrawals (per-UTxO)
_An authorized admin credential — a parameter of the spending script — rewrites
a wallet UTxO's delegated `withdrawals` list in place. Funds are untouched:
same address, same value — only the restriction set changes._

#let update_withdrawals_tx = vanilla_transaction(
  "Update withdrawals",
  inputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      redeemer: [UpdateWithdrawals],
      value: ("ada": "x"),
      datum: (
        withdrawals: "List(Credential)",
      ),
    ),
  ),
  outputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      value: ("ada": "x"),
      datum: (
        withdrawals: [*withdrawals'*],
      ),
    ),
  ),
  signatures: (
    "admin (if a key credential)",
  ),
  notes: [
    - the `admin` credential (a script parameter) must be satisfied: a key admin
      signs; a script admin authorizes by a withdraw-0 invocation (the same
      pluggable mechanism used elsewhere).
    - the continuation must sit at the same `wallet_addr` and carry the *same
      value* — an update cannot move funds, only swap the delegated
      `withdrawals` set. The admin is fixed in the script parameter, so control
      cannot be handed off.
    - `withdrawals'`: the new list. It takes effect immediately for subsequent
      spends of this UTxO; other wallet UTxOs are unaffected (the list is
      per-UTxO).
  ],
)

#figure(update_withdrawals_tx, caption: [Update withdrawals (per-UTxO)]) <fig:update-withdrawals>

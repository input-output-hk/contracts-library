// Smart Wallet — transaction design.
// A wallet with configurable restrictions; the primary implementation of the
// pluggable-authorization interface in ARCHITECTURE.md §2/§3. A multivalidator:
// a one-shot minting policy creates the wallet's identifying NFT, and a spending
// script holds the funds and checks a base M-of-N signature floor, delegating
// every other authorization to the withdraw-0 staking scripts listed in the
// wallet UTxO's own datum. One spend redeemer asserts the conjunction of the
// M-of-N floor and all delegated staking authorizations. An admin credential (a
// parameter of the script) creates the wallet, rewrites that list in place, and
// closes the wallet by burning the NFT.
//
// The M-of-N members and threshold are supplied as external configuration; this
// design is agnostic of how they are sourced (a settings UTxO, script
// parameters, another on-chain config, …), so only the spend's use of that
// config is shown.

#import "../diagrams-template.typ": *

#show: report

= Mint (create the wallet)
_The wallet is created by minting its identifying NFT — one token under the
script's own policy — into a fresh wallet UTxO at the wallet address. The
`admin` must authorize the mint._

#let mint_tx = vanilla_transaction(
  "Mint",
  inputs: (
    (
      name: "Seed UTxO",
      address: "seed_addr",
      value: ("ada": "s"),
    ),
  ),
  mint: (
    "wallet_nft": "1",
  ),
  outputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      value: (
        "ada": "x",
        "wallet_nft": "1",
      ),
      datum: (
        withdrawals: "[]",
      ),
    ),
  ),
  signatures: (
    "admin (if a key credential)",
  ),
  notes: [
    - `wallet_addr`: payment is `wallet_hash`, staking any. `wallet_hash =
      hash(smart_wallet(seed_utxo, settings_ref, wallet_nft_name, admin))` — the
      multivalidator is parameterized by its seed, configuration reference, NFT
      name, and the `admin` credential, so all wallet UTxOs share one address
      and one NFT policy.
    - one-shot: the mint requires the `seed_utxo` to be spent, and a UTxO can be
      spent at most once, so this policy id mints exactly one token ever. The
      resulting NFT is unforgeable and identifies the wallet.
    - the mint redeemer is `Mint { out_ix }`, locating the new wallet UTxO.
    - the new wallet UTxO carries the NFT, an inline datum with a `withdrawals`
      map, and no reference script. Every script in that map must be *published*
      in this same transaction (see [Publishing withdrawal scripts]) — so a
      wallet may be created already carrying delegated restrictions, but only
      ones that self-validated their initial data.
    - the `admin` credential (a script parameter) must be satisfied: a key admin
      signs; a script admin authorizes by a withdraw-0 invocation.
  ],
)

#figure(mint_tx, caption: [Mint (create the wallet)]) <fig:mint>

#pagebreak()

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
      value: (
        "ada": "x",
        "wallet_nft": "1",
      ),
      datum: (
        withdrawals: "Pairs<ScriptHash, Data>",
      ),
    ),
  ),
  withdrawals: (
    "each script in the wallet datum's withdrawals",
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
      value: (
        "ada": "x - y",
        "wallet_nft": "1",
      ),
      datum: (
        withdrawals: "Pairs<ScriptHash, Data>",
      ),
    ),
  ),
  signatures: (
    "any m of the n members",
  ),
  notes: [
    - `wallet_addr`: payment is `wallet_hash`, staking any. A wallet UTxO holds
      its identifying NFT plus ada and arbitrary native assets.
    - `wallet_hash = hash(smart_wallet(seed_utxo, settings_ref, wallet_nft_name,
      admin))`: the spending script is parameterized by its seed, configuration
      reference, NFT name, and the `admin` credential, so all wallet UTxOs share
      one address. Externalizing the members/threshold config lets it change
      without redeploying the script.
    - validity: the spend requires the wallet UTxO to carry its NFT (`1
      wallet_nft` under `wallet_hash`) — only NFT-bearing UTxOs are valid smart
      wallets.
    - base M-of-N floor: the wallet's configuration supplies `members` and
      `threshold`, and the spend requires at least `threshold` of `members`
      present in `extra_signatories`. A member may itself be a script
      credential, so the floor can be another multisig, a DAO, and so on. This
      design is agnostic of how that configuration is sourced.
    - delegated authorizations: every `ScriptHash` key in the wallet UTxO's
      `withdrawals` datum field is a withdraw-0 staking script that must run in
      this transaction; the `Data` value carries that script's own mutable
      state. The `Spend` redeemer asserts the conjunction — the M-of-N floor
      *and* all delegated checks — so no restriction can be silently omitted.
      The map is per-UTxO, so different wallet UTxOs may carry different
      restriction sets.
    - the delegated scripts are the extension point: spending limits, time
      locks, recipient allow-lists, oracle attestations, … each is an
      independent withdrawal script observed here, none known to the spending
      script.
    - composability: the spend asserts only its own inputs and that the
      required withdrawals ran — never the total input or output counts, nor
      unrelated UTxOs. Any partial change keeps the NFT so the wallet stays
      valid.
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
      value: (
        "ada": "x",
        "wallet_nft": "1",
      ),
      datum: (
        withdrawals: "Pairs<ScriptHash, Data>",
      ),
    ),
  ),
  outputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      value: (
        "ada": "x",
        "wallet_nft": "1",
      ),
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
      value* — including the NFT — so an update cannot move funds, only swap the
      delegated `withdrawals` set. The admin is fixed in the script parameter,
      so control cannot be handed off.
    - `withdrawals'`: the new list. It takes effect immediately for subsequent
      spends of this UTxO; other wallet UTxOs are unaffected (the list is
      per-UTxO).
    - the update diffs the old and new maps (see [Publishing withdrawal
      scripts]): every script *added* must be published here (a
      `RegisterCredential` certificate whose `publish` handler runs with the
      script's initial `Data` as its redeemer); every script *removed* must be
      unregistered (`UnregisterCredential`); every script *kept* must carry
      unchanged `Data`. This ensures each entry's `Data` was self-validated at
      registration and stays coherent across updates.
  ],
)

#figure(update_withdrawals_tx, caption: [Update withdrawals (per-UTxO)]) <fig:update-withdrawals>

#pagebreak()

= Publishing withdrawal scripts
_A withdraw-0 script joins a wallet's `withdrawals` map only after it is
_published_: its stake credential is registered via a `RegisterCredential`
certificate, which runs the script's `publish` handler. The handler reads its
own initial `Data` from the wallet output's datum and validates it, so no script
is delegated without first self-validating its own starting state. Removing a
script unregisters its credential, so re-adding it re-runs that validation._

#let publish_tx = vanilla_transaction(
  "Publish a withdrawal script",
  certificates: (
    "RegisterCredential { credential: Script(withdrawal_script_hash) }",
  ),
  notes: [
    - the `RegisterCredential` certificate references the script's stake
      credential, which triggers the script's `publish` handler (CIP-69
      certifying purpose).
    - the handler derives its own hash from the certificate and reads
      `withdrawals[own_hash]` out of the wallet output's inline datum — the
      single source of truth for the script's `Data` — and validates it.
    - the wallet only enforces that every script *added* to the `withdrawals`
      map has a matching `RegisterCredential` certificate (which implies its
      `publish` handler ran); all data validation is delegated to the script.
      `Mint` treats every script as added (there is no prior map).
    - removing a script requires an `UnregisterCredential` certificate for its
      credential, which also runs the script's `publish` handler; the credential
      is freed so a later add can register it (and validate its data) again.
    - the script's `publish` handler accepts an `UnregisterCredential` only when
      it sees itself listed in the wallet *input* datum and not in the wallet
      *output* datum (or there is no wallet output at all, as on `Close`). This
      prevents anyone from unregistering a script out of band, which would brick
      any wallet still delegating to it.
    - the reference `spending_limit` script is stateless (its `bound` is a
      compile-time parameter), so its `publish` handler only asserts the
      certificate registers or unregisters a script credential and that the
      script is listed in the wallet datum; a stateful script would additionally
      validate its initial `Data` here.
  ],
)

#figure(publish_tx, caption: [Publishing a withdrawal script]) <fig:publish>

#pagebreak()

= Close (admin burns the NFT)
_The admin closes the wallet: the wallet UTxO is spent, releasing whatever funds
remain, and the identifying NFT is burned. The `Close` spend redeemer requires
the admin, the burn, and that every delegated withdrawal script is unregistered
so its stake deposit is refunded; the `Burn` mint redeemer permits the burn._

#let close_tx = vanilla_transaction(
  "Close",
  inputs: (
    (
      name: "Wallet UTxO",
      address: "wallet_addr",
      redeemer: [Close],
      value: (
        "ada": "x",
        "wallet_nft": "1",
      ),
      datum: (
        withdrawals: "Pairs<ScriptHash, Data>",
      ),
    ),
  ),
  mint: (
    "wallet_nft": "-1",
  ),
  outputs: (
    (
      name: "Payout (remaining funds)",
      wallet: true,
      value: ("ada": "x"),
    ),
  ),
  signatures: (
    "admin (if a key credential)",
  ),
  notes: [
    - the `admin` credential (a script parameter) must be satisfied: a key admin
      signs; a script admin authorizes by a withdraw-0 invocation.
    - the wallet NFT — `1 wallet_nft` under `wallet_hash` — must be burned in
      this transaction (`-1`), destroying the wallet's identity. The burn runs
      the mint endpoint with a `Burn` redeemer, which only checks the burn
      quantity; authorization is enforced by the `Close` spend redeemer.
    - closing spends the wallet UTxO and releases any remaining funds. There is
      no continuation: once the NFT is gone, the wallet can no longer be spent.
    - every script in the closing wallet's `withdrawals` map must be unregistered
      here (`UnregisterCredential`), refunding its stake deposit. Each script's
      `publish` handler accepts this because it sees itself in the wallet input
      and no wallet output (see [Publishing withdrawal scripts]).
  ],
)

#figure(close_tx, caption: [Close (admin burns the NFT)]) <fig:close>

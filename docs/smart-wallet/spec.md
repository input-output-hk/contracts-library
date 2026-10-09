# Smart Wallet — Specification

> **Status: Draft (first version)** · Contract: `smart_wallet` · This document defines *what* the contract does, independently of the (`onchain/`) implementation and the transaction diagrams in [`design.typ`](./design.typ). It is the source of truth both implementations aim to match. See [`ARCHITECTURE.md`](../ARCHITECTURE.md) §2.3.

## 1. Summary

A **smart wallet** holds funds on-chain behind a *configurable* set of spending
restrictions. It is a multivalidator — a one-shot minting policy that creates the
wallet's identifying NFT, plus a spending script — with a fixed **base M-of-N
signature floor** and a list of **delegated withdrawal scripts** that run on every
spend. Any authorization beyond the floor is expressed as an independent
withdraw-0 staking script, so a wallet's restrictions are open-ended (spending
limits, time locks, recipient allow-lists, …) without the spending script knowing
anything about them. **Deposit scripts** use the same mechanism to validate
funds added to the wallet (asset/address allow-lists, …).

Three roles interact with a wallet:

- the **admin** (a validator *parameter*) creates, reconfigures, and closes the wallet;
- the **depositors** (delegated scripts in the datum) may add funds, but never
  spend them or change the config;
- **spending** requires the base M-of-N floor *and* every delegated spender script.

The members and threshold of the M-of-N floor are **not** baked into the wallet;
they are read from an external settings UTxO, so they can change without
redeploying the wallet script.

## 2. Status & roadmap

This is a **first version**. It is a working implementation of the pluggable
authorization direction of [`ARCHITECTURE.md`](../ARCHITECTURE.md) §3, but it is
not intended to be the final shape of the protocol. Two changes are already
envisioned for a future version:

1. **Drop `admin` as a validator parameter.** Today the admin is a compile-time
   parameter of the spending/minting script, which makes it immutable without a
   redeployment. The intent is to express admin authorization as an *ordinary
   delegated withdrawal script* — just another entry in the wallet's
   `spenders` map — so "who may reconfigure/close the wallet" is itself a
   pluggable, updatable restriction rather than a hardcoded special case.

2. **Make withdrawal scripts shared.** Today a withdrawal script is parameterized
   by a specific `wallet` credential (its hash differs per wallet), and `Mint`
   treats every script in the initial `spenders`/`depositors` maps as newly
   registered. That prevents one script instance — and the mutable state it
   carries — from being delegated by more than one wallet. The intent is to remove the per-wallet
   parameter (scripts observe the wallet they are invoked for from the
   transaction, not from their own hash) so a single script instance can be
   shared across wallets, and to relax the "everything is newly added at mint"
   assumption accordingly.

These are *directional*, not committed: the current shape is deliberately simple
to validate the core mechanism (NFT identity, M-of-N floor, delegated
withdraw-0 scripts, and per-script mutable state) before generalizing it.

## 3. Roles

- **Admin** (`admin`, a validator parameter). Creates the wallet (mint), rewrites
  its config (`UpdatePermissions`), and closes it (`Close`). A `Credential`, so a key,
  multisig, DAO, or smart wallet can fill the role. It has no power over
  individual spends, and (being a parameter) it is fixed for the life of the
  script address.
- **Deposit scripts** (the `depositors` map). Each must run and approve on every
  `Deposit`; they carry the validation logics that specialize what may be
  deposited (asset allow/denylists, source-address checks, …). Rewritable by the
  admin via `UpdatePermissions`; with an empty map, deposits are open.
- **Members** (from the external settings config). The base M-of-N floor: at
  least `threshold` of `members` must sign a `Spend`. A member may itself be a
  script credential, so the floor can be a multisig, a DAO, etc.
- **Delegated spender scripts** (the `spenders` map). Each must run and
  approve on every `Spend`; they carry the restrictions that specialize a wallet
  beyond its floor.

## 4. State model

A wallet is a single UTxO, uniquely identified by its **wallet NFT** and locked
at the wallet address (payment credential `Script(wallet_hash)`), where
`wallet_hash` is the hash of the parameterized `smart_wallet` validator.

### 4.1 Datum (inline)

| Field | Type | Meaning |
|---|---|---|
| `spenders` | `Pairs<ScriptHash, Data>` | The delegated withdraw-0 scripts that must run on every `Spend`, keyed by script hash. The `Data` value is that script's own mutable state. |
| `depositors` | `Pairs<ScriptHash, Data>` | The delegated withdraw-0 scripts that must run on every `Deposit`, keyed by script hash. The `Data` value is that script's own configuration or mutable state (e.g. an asset allow/denylist, or a deposit counter). |

The datum is **inline** (datum hashes are rejected). Both maps are
per-UTxO: different wallet UTxOs may carry different restriction sets.

### 4.2 Identity & one-shot mint

The wallet NFT is minted exactly once under the script's own policy: `Mint`
requires spending the parameterized `seed_utxo`, and a UTxO can be spent at most
once, so the policy mints a single token ever. The NFT is unforgeable and
identifies the wallet; only an NFT-bearing UTxO at the wallet address is a valid
wallet. The NFT never leaves the wallet UTxO except on `Close`, where it is
burned: `Spend` requires the wallet to survive, carrying the NFT (and its
`depositors`) forward (§5.2).

### 4.3 Redeemers

**Spend** (on the wallet UTxO):

| Redeemer | Action |
|---|---|
| `Spend` | Pay out: base M-of-N floor **and** every delegated spender script runs. |
| `UpdatePermissions { out_ix }` | Admin rewrites `spenders` and/or `depositors`. |
| `Deposit { out_ix }` | Every `depositors` script runs and approves; funds are added, config and value otherwise preserved. |
| `Close` | Admin closes: burn the NFT, release funds, unregister every script. |

**Mint** (under `wallet_hash`):

| Redeemer | Action |
|---|---|
| `Mint { out_ix }` | Create the wallet: mint the NFT once, into a fresh wallet UTxO. |
| `Burn` | Mint-side of `Close`: burn the NFT. |

`out_ix` locates the continuation (wallet) output in the transaction.

## 5. Action set

Authorization throughout uses a pluggable `Credential`: a key authorizes by
signing (appearing in `extra_signatories`); a script authorizes by being invoked
via a **reward withdrawal** in the same transaction (withdraw-0 pattern).

### 5.1 Mint (create)

| | |
|---|---|
| **Inputs** | The parameterized `seed_utxo` (one-shot). |
| **Outputs** | One **wallet UTxO** at `out_ix`: payment credential `Script(wallet_hash)`, carrying the NFT, an **inline** datum, no reference script. |
| **Mint** | Exactly one token under `wallet_hash` with the parameterized name, quantity `1`. |
| **Redeemer** | `Mint { out_ix }`. |
| **Authorization** | `admin`. |
| **Constraints** | Every script in the initial `spenders` and `depositors` maps must be **published** in this same transaction (see §6): a `RegisterCredential` certificate for its stake credential, whose `publish` handler validates the script's initial `Data`. |

### 5.2 Spend

| | |
|---|---|
| **Inputs** | One wallet UTxO carrying the NFT. |
| **Outputs** | Must include a **wallet continuation**: an NFT-bearing output at the wallet's payment credential carrying an inline `WalletDatum` with the same `depositors` map as the input. Payout outputs are otherwise unconstrained. |
| **Redeemer** | `Spend`. |
| **Authorization** | At least `threshold` of `members` sign (read from the settings UTxO), **and** every script in `spenders` is invoked as a reward withdrawal and approves. |
| **Constraints** | The wallet UTxO carries its NFT; the delegated spender scripts' `withdraw` handlers run and each enforces its own restriction; the wallet survives with `depositors` unchanged and the `spenders` key set fixed — adding or removing delegated scripts is reserved for `UpdatePermissions`, while spender `Data` may change (each script enforces its own transition). |

The `Spend` branch asserts only its own input, the M-of-N floor, that the
required spender scripts ran, and that the wallet survives with its `depositors`
unchanged and its `spenders` key set fixed — never total input/output counts or
unrelated value.

### 5.3 UpdatePermissions

| | |
|---|---|
| **Inputs** | The wallet UTxO. |
| **Outputs** | One continuation at `out_ix`: same address, same value (NFT preserved), inline datum with the new config. |
| **Redeemer** | `UpdatePermissions { out_ix }`. |
| **Authorization** | `admin`. |
| **Constraints** | The old and new `spenders` and `depositors` maps are diffed: every script *added* must be **published** here (`RegisterCredential`); every script *removed* must be **unregistered** (`UnregisterCredential`); every script *kept* must carry unchanged `Data`. |

Funds cannot move: the continuation sits at the same address with value `>=` the
input (in fact, only ADA may change, to cover fees).

### 5.4 Deposit

| | |
|---|---|
| **Inputs** | The wallet UTxO (plus the depositing party's own funding UTxOs). |
| **Outputs** | One continuation at `out_ix`: same address, `spenders` unchanged, `depositors` keys unchanged with `Data` possibly advanced, value a **superset** of the input's (every asset, including lovelace and the NFT, present in `>=` quantity). |
| **Redeemer** | `Deposit { out_ix }`. |
| **Authorization** | Every script in `depositors` is invoked as a reward withdrawal and approves; with an empty map, no approval is needed. |
| **Constraints** | The `spenders` map is preserved and the `depositors` key set is fixed; depositor `Data` may advance, with each deposit script enforcing its own transition. The `spenders` scripts do **not** run (there is no outflow to restrict). |

### 5.5 Close

| | |
|---|---|
| **Inputs** | The wallet UTxO. |
| **Outputs** | No continuation; the remaining funds may go anywhere. |
| **Mint** | The NFT is burned: exactly one token under `wallet_hash`, quantity `-1`. |
| **Redeemer** | `Close` (spend) **and** `Burn` (mint). |
| **Authorization** | `admin`. |
| **Constraints** | Every script in the wallet's `spenders` and `depositors` maps must be **unregistered** here (`UnregisterCredential`), refunding its stake deposit. |

Closing is irreversible: the NFT is gone and the seed nonce is spent, so the
wallet can never be relaunched at this script address.

## 6. Withdrawal scripts

A delegated script is a **withdraw-0 staking script**. It is not known to the
spending script beyond its hash and its entry in the `spenders` or `depositors`
map; it participates through two script purposes:

- **`publish`** (triggered by a delegation certificate referencing the script's
  stake credential). On `RegisterCredential`, the handler reads its own initial
  `Data` from the wallet **output** datum and validates it — so a script cannot be
  delegated without self-validating its starting state. On
  `UnregisterCredential`, the handler accepts the removal only if the script is
  actually **leaving** the wallet (listed in the wallet *input* datum, absent from
  the *output* datum, or no output at all on `Close`); this prevents unregistering
  a script out of band, which would brick any wallet still delegating to it.

- **`withdraw`** (a reward withdrawal, required by `Spend` for spender scripts
  and by `Deposit` for deposit scripts). The handler enforces the script's own
  requirement. A **stateful spender** script reads its current `Data` from the
  wallet *input* datum, computes the transition, and requires the wallet *output*
  datum to record the new state.

The `Data` value in `spenders[script_hash]` is that script's mutable state:
stateless scripts store a trivial marker (e.g. `spending_limit`, whose `bound` is
a compile-time parameter); stateful scripts store and advance real state (e.g.
`spending_window`, which tracks the last spend time to limit spends per window).
`depositors[script_hash]` works the same way on the deposit side: stateless
deposit scripts store static configuration (e.g. an asset allow/denylist), while
stateful ones advance real state on each `Deposit` (e.g. a deposit cap per
window), enforcing their own input→output transition.

> **Well-formed delegated scripts (trust).** A delegated script is the sole
> authority over its own `Data`: the core enforces the `spenders` key set and
> `depositors` immutability across spends, but never an entry's size or
> semantics. A buggy or malicious script can therefore:
>
> - **grow its entry without bound** (bounded only by the ledger's transaction
>   size limit), bloating the wallet UTxO. Because `Deposit` copies `spenders`
>   byte-identically and `UpdatePermissions` keeps surviving entries unchanged,
>   the payload is carried by every later transaction and can make spends,
>   deposits, and updates fail.
> - **rewrite its own state arbitrarily** if its `withdraw` handler does not
>   verify the input→output transition.
> - **refuse to cooperate**: a script whose `publish` handler rejects
>   `UnregisterCredential` cannot be removed and blocks both `Close` and
>   `UpdatePermissions` removal, leaving the funds stranded.
>
> Delegate only reviewed scripts (at `Mint` or `UpdatePermissions`), and never
> read or trust another entry's `Data` — a script may rely on its own only.

## 7. Invariants

- **I1 — NFT identity.** A valid wallet is exactly the NFT-bearing UTxO at the
  wallet address; the NFT is minted once (one-shot seed), kept in the wallet by
  every `Spend`, and burned only on `Close`.
- **I2 — Spend authorization.** A `Spend` is valid only if the M-of-N floor is
  met and every script in `spenders` is invoked and approves.
- **I3 — Config-only updates.** `UpdatePermissions` preserves address and value; only
  `spenders` and `depositors` may change, and only by the `admin`.
- **I4 — Published additions.** A script may appear in `spenders` or `depositors`
  only if it was registered (its `publish` handler validated its initial `Data`)
  in the same transaction — at `Mint` or on `UpdatePermissions`. A `Spend` may
  not add one: it keeps the `spenders` key set fixed.
- **I5 — Unregistered removals.** A script leaving `spenders` or `depositors` (on
  `UpdatePermissions` or `Close`) must be unregistered in the same transaction. A
  `Spend` may not remove one.
- **I6 — Deposit adds, never removes.** `Deposit` preserves `spenders` and the
  `depositors` key set and only increases value, and every `depositors` script
  must run and approve (with an empty map, deposits are open); depositor `Data`
  may advance only through those scripts' own handlers, and a deposit can never
  spend funds or change the permission set.
- **I7 — State coherence.** A stateful script's `withdraw` enforces its own
  transition by reading the input state and requiring the output state to match
  (on `Spend` for spender scripts, on `Deposit` for deposit scripts); kept
  scripts carry unchanged `Data` across an `UpdatePermissions`.
- **I8 — Composability.** Each endpoint asserts only its own input, the mint under
  its own policy, the `out_ix` output, the validity range, and the required
  authorization; never total input/output counts or unrelated value.
- **I9 — Depositor set is admin-only.** The `depositors` key set changes only
  through `UpdatePermissions`, and a `Spend` must recreate the wallet with the
  whole map unchanged; its values advance only through deposit scripts on
  `Deposit`. Neither a spend nor moving the NFT out and back can alter deposit
  validation.

## 8. Threat model & assumptions

### Defended

- **Unauthorized spend.** Blocked by the M-of-N floor plus the delegated-script
  conjunction (I2). No single member or script can spend alone.
- **Config tampering / control handoff.** `UpdatePermissions` requires the `admin`
  (fixed at deploy) and cannot move funds (I3); the admin cannot be changed, so
  control cannot be handed off without redeployment.
- **Deposit-rule tampering.** Only the `admin`'s `UpdatePermissions` can change
  `depositors`: `Deposit` preserves the datum and `Spend` must keep the wallet
  and its `depositors` map unchanged (I9). M-of-N authority cannot rewrite
  deposit validation — the NFT cannot leave the wallet on a `Spend`, so it cannot
  be re-sent with a crafted datum either.
- **Draining via deposit.** `Deposit` preserves the datum and only increases value
  (I6); a deposit can never withdraw, and configured `depositors` scripts gate
  what may be added.
- **Out-of-band unregister (DoS).** A script's `publish` handler rejects
  `UnregisterCredential` unless the script is leaving a wallet (I5), so an
  attacker cannot unregister a delegated script and thereby stop the wallet from
  spending or accepting deposits.
- **Restriction dropping.** A `Spend` preserves the delegated-script set: it may
  not add or remove entries in `spenders` (I4/I5), so an approved spend cannot
  silently shrug off a restriction or leave a stake credential registered without
  a map entry. Removing a spender requires `UpdatePermissions` and its
  unregistration certificate.
- **Unvalidated script state.** A script enters `spenders` or `depositors` only
  after its own `publish` handler validates its initial `Data` (I4); stateful
  transitions are enforced by the script on every spend or deposit (I7).

### Assumptions / out of scope

- **First version (see §2).** `admin` is a compile-time parameter and withdrawal
  scripts are wallet-parameterized; both are slated to change.
- **Settings config is trusted.** The M-of-N `members`/`threshold` are read from an
  external settings UTxO; the wallet does not validate that contract.
- **Min-ada / surplus value.** A wallet UTxO may hold ADA beyond what restrictions
  reference; only the delegated scripts' own checks (if any) constrain it.
- **Open deposits.** A wallet with an empty `depositors` map accepts deposits from
  anyone; the core only preserves the spend side and the `depositors` key set and
  requires added value. Use deposit scripts to gate who and what may be deposited.
- **Delegated scripts are trusted to be well-formed.** The core validates
  neither the size nor the semantics of an entry's `Data` (see §6): a buggy or
  malicious script can grief the wallet through datum bloat, unchecked state
  rewrites, or refusing unregistration (which blocks `Close` and removal). Vet
  scripts before delegating them.
- **The wallet is a single UTxO.** The one-shot NFT guarantees one identity; the
  protocol does not model a multi-UTxO wallet.
- **Time.** The core wallet does not read a clock. Stateful scripts that need time
  (e.g. `spending_window`) read `now` as the **lower bound of the validity
  range**, and the ledger's guarantee `real_slot >= lower_bound` is an axiom for
  their soundness.

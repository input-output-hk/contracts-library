# DAO Protocol Specification

## 1. Summary

Token-based governance of a protocol and its treasury: token holders **stake** tokens into positions, **propose** actions, **vote** with weight proportional to their stake, and, if thresholds are met, a proposal resolves to an **effect** script that can execute the approved action.

The protocol is a set of three cooperating validators, each guarding its own single-NFT-threaded UTxO type, plus user-supplied per-option **effect** scripts:

- **`stake`** — a *stake position* UTxO holds a holder's staked tokens and records the locks that freeze them while a proposal is live. The validator's own hash is the stake-NFT policy id and the position address.
- **`proposal`** — a *proposal* UTxO carries a governance proposal through its lifecycle (Draft → Voting → Tally → closed). The validator's own hash is the proposal-NFT policy id and the proposal address.
- **`vote`** — a *vote artifact* UTxO records one holder's vote on one proposal and is destroyed at tally time. The validator's own hash is the vote-NFT policy id and the vote address.
- **Effect scripts** — the per-option validators a proposal references in its `results`. They are *not* part of the protocol; a proposal just names them, and the winning one runs under the withdraw-0 convention.

Governance parameters (thresholds, timings, and the sibling script hashes) are **not** compiled into the validators. They are read at runtime from a **settings UTxO** (see `specs/settings/protocol-settings.md`), located by its NFT via reference input, whose opaque `current` datum is cast to `DaoSettings`. This keeps the three DAO validators free of circular compile-time dependencies and lets the settings protocol govern the DAO's parameters.

### Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| State identity | **Three NFT-guarded UTxO types** | Stake, proposal, and vote each live in one UTxO identified by a token whose policy id *is* the validator's own hash. |
| NFT uniqueness | **Name = hash of a consumed `OutputReference`** | Hashing a spent output reference yields a globally unique, unforgeable token name, so every position/proposal/vote is unique by construction. |
| Governance params | **Read from a settings UTxO at runtime** | Avoids cyclic compile-time parameterization and lets the settings protocol govern the DAO. |
| Double-vote prevention | **Stake locks (freeze `max`, not sum)** | The same tokens back every concurrent action, so a position with `N` tokens can lend all `N` to several proposals at once; the frozen amount is the *maximum* committed stake across live locks. |
| Lifecycle | **Immutable proposal body, evolving `status`** | `thresholds`, `timing_config`, `start_time`, and `results` are locked at creation; only `status` evolves. |
| Execution | **`results`-bound effect scripts, withdraw-0** | A proposal binds each option to a script hash; the winner runs as a reward withdrawal and must verify its own victory via `am_i_the_winner`. |
| Authorization | **Pluggable `Credential`** | `owner`/`delegatee` are `Credential`s, so keys, multisigs, DAOs, or smart wallets can hold, propose, cosign, and vote. |

## 2. Roles

- **Owner** (a `Credential` in a stake position): deposits, withdraws, delegates, closes the position, and creates proposals. Authorizes by key signature or by script invocation (withdraw-0).
- **Delegatee** (optional `Credential` in a stake position): when set, authorizes cosigning and voting on behalf of the position. The owner remains in control of deposits/withdrawals/closing/delegation/creation.
- **Proposer / Cosigner / Voter**: any holder of a sufficiently-staked position performing those actions.
- **Settings authority**: the party (or parties) able to change the `DaoSettings` via the settings protocol. The DAO validators trust that the settings UTxO's `current` datum, located by its NFT, is a well-formed `DaoSettings`.
- **Effect (poll) scripts**: per-option validators referenced by a proposal's `results`. Each must independently prove it is the winner of a legitimately-closed poll; the protocol does not trust them to be well-behaved.
- **Consumers**: contracts or parties that read proposal/settings state via reference inputs, or that run effect scripts.

## 3. State model

### 3.1 Script parameters

Baked into each script hash (all four are parameterized):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `staked_token_policy` | `PolicyId` | Policy of the governance token. |
| `staked_token_name` | `AssetName` | Name of the governance token. |
| `settings_policy` | `PolicyId` | Policy of the settings NFT (the settings script's own hash). |
| `settings_token_name` | `AssetName` | Name of the settings NFT. |
| `proposal_policy` | `PolicyId` | (effect scripts only) The proposal validator's own hash, pinned at compile time. |

The `stake`, `proposal`, and `vote` validators share the first four parameters. The `poll_effect` reference effect is parameterized only by `proposal_policy`.

### 3.2 The settings bridge (`DaoSettings`)

Each DAO action resolves the settings UTxO — the reference input holding `settings_token_name` under `settings_policy` — and casts its inline datum's `current` field (an opaque `Data` in the settings contract) to:

| Field | Type | Meaning |
| --- | --- | --- |
| `thresholds` | `ProposalThresholds` | Governance thresholds (in staked-token units). |
| `timings` | `ProposalTimingConfig` | Phase durations (POSIX milliseconds). |
| `stake_validator` | `ScriptHash` | Stake validator hash (also the stake-NFT policy id). |
| `proposal_validator` | `ScriptHash` | Proposal validator hash (also the proposal-NFT policy id). |
| `vote_validator` | `ScriptHash` | Vote validator hash (also the vote-NFT policy id). |

```aiken
ProposalThresholds    = { create, cosign, accept, vote, execute : Int }
ProposalTimingConfig  = { draft_length, voting_length, tally_length : Int }
```

The cast is a hard `expect`: if the settings `current` datum is not a `DaoSettings`, the DAO action fails closed (rejected), never unsafely.

### 3.3 Datums

**Stake position** (inline, on the stake address):

| Field | Type | Meaning |
| --- | --- | --- |
| `owner` | `Credential` | Who may deposit/withdraw/delegate/close/create. |
| `delegatee` | `Option<Credential>` | If set, who may cosign/vote on this position. |
| `locks` | `List<Lock>` | Live locks freezing stake; `Lock { proposal_id: ByteArray, unlock_time: Int, stake: Int }`. |

The **frozen** stake of a position is `max(lock.stake)` over all locks (0 when empty); the **free** stake is `total - frozen`. A lock is **expired** when `unlock_time <= now`; expired locks are dropped by `prune_expired`.

**Proposal** (inline, on the proposal address):

| Field | Type | Meaning |
| --- | --- | --- |
| `thresholds` | `ProposalThresholds` | Copied from settings at creation; immutable thereafter. |
| `timing_config` | `ProposalTimingConfig` | Copied from settings at creation; immutable. |
| `start_time` | `Int` | POSIX ms of creation (the create transaction's validity lower bound). |
| `status` | `ProposalStatus` | The only mutable field. |
| `results` | `List<ScriptHash>` | Per-option effect script hash; index = option id. |

`ProposalStatus` is the lifecycle state machine:

```
Draft { cosigning_stake: Int }  — accumulating cosign stake
Voting                          — votes are accepted
Tally { votes: List<Int> }      — vote totals per option, being accumulated
```

The transition graph (see §4 for exact per-action conditions):

```
                 Cosign (accumulate)                    AcceptDraft
Draft ──────────────────────────────► Draft ─────────────► Voting
   │                                    │                    │
   └── RejectDraft (burn) ◄─────────────┘                    │ EndVotingStage
                                                             ▼
                                             Tally ◄─────────┘
                                               │
                                               ├── TallyVotes (accumulate)
                                               └── EndProposal (burn + execute winner)

```

**Vote artifact** (inline, on the vote address):

| Field | Type | Meaning |
| --- | --- | --- |
| `stake_owner` | `Credential` | The stake position's `owner` at vote time (who may `Cancel`). |
| `proposal` | `ByteArray` | The proposal token name the vote belongs to. |
| `voted_option` | `Int` | Index into the proposal's `results`. |
| `stake` | `Int` | The staked amount that weights this vote at tally. |

### 3.4 Redeemers

**`stake`** — mint (`StakePositionTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `CreatePosition { owner_utxo, out_idx }` | Mint a position NFT; create the position UTxO. |
| `CloseStakePosition` | Mint side of closing: burn exactly one position NFT. |

**`stake`** — spend (`StakeRedeemer`):

| Redeemer | Action |
| --- | --- |
| `Deposit` | Owner adds stake (or prunes locks). |
| `DelegateTo { delegatee: Option<Credential> }` | Owner sets, changes, or clears (`None`) the delegatee. |
| `Withdraw { amount }` | Owner withdraws free stake. |
| `ClosePosition` | Owner closes the position (all locks expired). |
| `CreateProposal` | Owner creates a proposal (records a lock). |
| `CosignProposal { proposal_id }` | Cosign a draft proposal (records a lock). |
| `VoteProposal { proposal_id, voted_option }` | Vote on a proposal (records a lock). |

**`proposal`** — mint (`ProposalTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `MintProposal { results, out_idx }` | Mint a proposal NFT; create the proposal UTxO. |
| `BurnProposal` | Mint side of reject/end: burn proposal NFTs. Admits **batch burns** so `RejectDraft` and `EndProposal` share one endpoint. |

**`proposal`** — spend (`ProposalRedeemer`):

| Redeemer | Action |
| --- | --- |
| `Cosign` | Add a cosignature's stake to a draft. |
| `AcceptDraft` | Promote Draft → Voting once the accept threshold is met. |
| `RejectDraft` | Destroy a draft after its deadline. |
| `EndVotingStage` | Promote Voting → Tally after the voting deadline. |
| `TallyVotes` | Consume and count votes during the tally window. |
| `EndProposal { winner }` | Close the poll after the tally deadline; declare the winner. |

**`vote`** — mint (`VoteTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `MintVote { out_idx }` | Mint a vote NFT; create the vote artifact UTxO. |
| `BurnVotes` | Mint side of tally/cancel: burn vote NFTs. |

**`vote`** — spend (`VoteRedeemer`):

| Redeemer | Action |
| --- | --- |
| `TallyVote` | Consume a vote as part of tallying its proposal. |
| `Cancel` | Owner cancels the vote before tally (burns its NFT). |

**Effect scripts** (`poll_effect` reference): a `withdraw` endpoint under the withdraw-0 convention whose redeemer is entirely private to the script (`Data` in the reference). The protocol never inspects it.

### 3.5 Value and NFT conventions

- Each validator's **own hash is its NFT policy id and its address payment credential**: `Script(policy)`.
- A position holds **one** stake NFT under the stake policy (name = `blake2b_256(serialise(owner_utxo))`), plus staked tokens and lovelace. On create/deposit/withdraw the value must contain *nothing else*: exactly three flattened entries (lovelace + the NFT + the staked token).
- A proposal holds **one** proposal NFT (name = hash of the creating stake UTxO's reference). Continuations must preserve it.
- A vote artifact holds **one** vote NFT (name = hash of the voting stake UTxO's reference) plus lovelace.
- **Uniqueness consequences.** Because a token name is the hash of a *consumed* output reference, it can never be minted again: a position can originate **at most one proposal** over its entire lifetime, and each vote artifact is globally unique even for repeated votes from the same position (each vote spends a distinct stake UTxO).
- **NFT-quantity strictness.** Proposal and vote continuation/creation outputs must hold **exactly one** own-policy NFT; the stake creation output requires at least one.
- Continuation outputs are located by **address** (equal to the spent input's address) for stake/proposal; by explicit `out_idx` for the mint-created outputs. The address lookup matches the **first** such output: a builder must never place two contract outputs at the same address in one transaction, since the validator does not enforce that uniqueness. Inline datums and no reference script are required throughout.

## 4. Transactions

All possible protocol transactions, grouped by validator. "The own input" is the contract UTxO being spent; cross-references to sibling inputs/outputs are checked locally and each sibling's own validator re-checks its detailed constraints.

### 4.1 Stake: Create Position

| | |
| --- | --- |
| **Inputs** | The `owner_utxo` (must be spent). Any wallet UTxOs funding the staked tokens. |
| **Mint** | Exactly one token under the stake policy, name = hash of `owner_utxo`, quantity `1`. |
| **Outputs** | One position at `out_idx`: address `Script(stake_policy)`, value = NFT + ≥ 1 staked token + lovelace (exactly three assets), inline datum, no reference script. |
| **Datum** | `StakePositionDatum { owner: payment_credential(owner_utxo), delegatee: None, locks: [] }`. |
| **Redeemer** | mint `CreatePosition { owner_utxo, out_idx }`. |
| **Authorization** | None. The owner is the payment credential of the consumed `owner_utxo`; ownership is established by proof-of-spend, not a signature. |

### 4.2 Stake: Deposit

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(locks, now)`, staked token `>=` the spent amount, NFT quantity `1`, exactly three assets. |
| **Redeemer** | `Deposit`. |
| **Authorization** | `owner` satisfied. |
| **Validity range** | Lower bound finite (`now`). |

### 4.3 Stake: DelegateTo

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner unchanged, `delegatee = delegatee` (set, changed, or cleared with `None`), `locks` unchanged (not pruned), value a superset of the spent value (`match(out, own, >=)`). |
| **Redeemer** | `DelegateTo { delegatee }`. |
| **Authorization** | `owner` satisfied. |
| **Validity range** | Unconstrained. |

### 4.4 Stake: Withdraw

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(locks, now)`, staked token `= in_stake - amount`, NFT quantity `1`, exactly three assets. The withdrawn amount may go anywhere. |
| **Redeemer** | `Withdraw { amount }`. |
| **Authorization** | `owner` satisfied. |
| **Validity range** | Lower bound finite (`now`). |
| **Constraint** | `0 <= amount <= free_stake(in_stake, prune_expired(locks, now))`. |

### 4.5 Stake: Close Position

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Mint** | The position NFT is burned (quantity `-1`). |
| **Outputs** | No continuation required; remaining stake/ada may go anywhere. |
| **Redeemer** | `ClosePosition` (and mint `CloseStakePosition`). |
| **Authorization** | `owner` satisfied. |
| **Validity range** | Lower bound finite (`now`); **all locks must be expired** (`prune_expired(locks, now) == []`). |

### 4.6 Stake: Create Proposal (stake side)

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Mint** | Exactly one proposal NFT minted under `proposal_validator`, name = hash of this position's reference, quantity `1`. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = push(locks, Lock { proposal_id, now + draft_length, in_stake })`, value a superset of the spent value. |
| **Redeemer** | `CreateProposal`. |
| **Authorization** | `owner` satisfied. |
| **Validity range** | Lower bound finite (`now`). |
| **Constraint** | `in_stake >= settings.thresholds.create`. |

### 4.7 Stake: Cosign (stake side)

| | |
| --- | --- |
| **Inputs** | The position UTxO, and the proposal UTxO (spent). |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = concat(locks, [Lock { proposal_id, proposal.start_time + proposal.draft_length, in_stake }])`, value a superset of the spent value. |
| **Redeemer** | `CosignProposal { proposal_id }`. |
| **Authorization** | `vote_auth` (delegatee if set, else owner). |
| **Validity range** | Unconstrained (the deadline is enforced by the proposal's `Cosign` side). |
| **Constraint** | The proposal is `Draft`; `in_stake >= proposal.thresholds.cosign`; the position has no lock for `proposal_id` (`!has_proposal`). |

### 4.8 Stake: Vote (stake side)

| | |
| --- | --- |
| **Inputs** | The position UTxO (spent); the proposal UTxO (reference input). |
| **Mint** | Exactly one vote NFT minted under `vote_validator`, name = hash of this position's reference, quantity `1`. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(concat(locks, [Lock { proposal_id, start + draft + voting, in_stake }]), now)`, value a superset of the spent value. |
| **Redeemer** | `VoteProposal { proposal_id, voted_option }` (`voted_option` is ignored here; the vote mint validates it). |
| **Authorization** | `vote_auth` (delegatee if set, else owner). |
| **Validity range** | Lower and upper bounds finite; `upper <= start + draft + voting`. |
| **Constraint** | The proposal is `Voting`; `in_stake >= proposal.thresholds.vote`; no existing lock for `proposal_id`. |

### 4.9 Proposal: Create (proposal side)

| | |
| --- | --- |
| **Inputs** | A stake input holding an NFT under `stake_validator` (spent). |
| **Mint** | Exactly one token under the proposal policy, name = hash of the stake input's reference, quantity `1`. |
| **Outputs** | One proposal at `out_idx`: address `Script(proposal_policy)`, value holds the NFT and nothing extra, inline datum, no reference script. |
| **Datum** | `ProposalDatum { thresholds: settings.thresholds, timing_config: settings.timings, start_time: now, status: Draft { cosigning_stake: staked_amount }, results }`. |
| **Redeemer** | mint `MintProposal { results, out_idx }`. |
| **Authorization** | None directly; requires the stake input to be consumed with `CreateProposal` (the stake side enforces owner auth). |
| **Validity range** | Lower bound finite (`now` = `start_time`). |
| **Constraint** | `staked_amount >= settings.thresholds.create`. |

### 4.10 Proposal: Cosign (proposal side)

| | |
| --- | --- |
| **Inputs** | The proposal UTxO, and the cosigning stake UTxO (spent). |
| **Outputs** | One continuation at the same address with status `Draft { cosigning_stake: n + s }` (`s` = the cosigner's staked amount); immutables preserved. |
| **Redeemer** | `Cosign`. |
| **Authorization** | None directly; requires the stake input consumed with `CosignProposal { proposal_id }`. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length`. |
| **Precondition** | Status is `Draft { cosigning_stake: n }`. |

### 4.11 Proposal: Accept Draft

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Outputs** | One continuation at the same address with status `Voting`; immutables preserved. |
| **Redeemer** | `AcceptDraft`. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length`. |
| **Precondition** | Status `Draft { cosigning_stake: n }` with `n >= thresholds.accept`. |

### 4.12 Proposal: Reject Draft

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Mint** | The proposal NFT is burned. |
| **Outputs** | No continuation. |
| **Redeemer** | `RejectDraft` (and mint `BurnProposal`). |
| **Validity range** | Lower bound finite and `>= start_time + draft_length`. |
| **Precondition** | Status `Draft`. |

### 4.13 Proposal: End Voting Stage

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Outputs** | One continuation at the same address with status `Tally { votes: [0 × len(results)] }`; immutables preserved. |
| **Redeemer** | `EndVotingStage`. |
| **Validity range** | Lower bound finite and `>= start_time + draft_length + voting_length`. |
| **Precondition** | Status `Voting`. |

### 4.14 Proposal: Tally Votes

| | |
| --- | --- |
| **Inputs** | The proposal UTxO, plus one or more vote UTxOs (spent, consumed with `TallyVote`). |
| **Mint** | Each consumed vote's NFT is burned (quantity `-1` under the vote policy). |
| **Outputs** | One continuation at the same address with status `Tally { votes: counted }`; immutables preserved. Each consumed vote's lovelace is refunded to an output whose payment credential is its `stake_owner`, holding **at least** the vote UTxO's lovelace. |
| **Redeemer** | `TallyVotes`. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length + voting_length + tally_length`. |
| **Precondition** | Status `Tally { votes }`; at least one vote consumed; the number of burned vote tokens equals the number of votes counted for *this* proposal. |

Votes whose recorded `voted_option` falls outside `0 .. len(results) - 1` are consumed and burned but their stake is **silently dropped** from the tally. `MintVote` already rejects such options, so this is defense in depth against hand-forged artifacts.

### 4.15 Proposal: End Proposal

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Mint** | The proposal NFT is burned (quantity `-1`). |
| **Outputs** | No continuation. |
| **Redeemer** | `EndProposal { winner }` (and mint `BurnProposal`). |
| **Validity range** | Lower bound finite and `>= start_time + draft_length + voting_length + tally_length`. |
| **Withdrawals** | If `winner = Some(effect)`, a withdrawal keyed by `Script(effect)` must be present (the effect runs). |

The declared `winner` must match the tally: the **strict winner** of `votes` (a unique option with the highest total and no tie, total `> 0`); if that total is `>= thresholds.execute`, the expected effect is `results[option]`, otherwise `None` (no outcome qualifies for execution). `winner` must equal this expected value exactly.

Losing candidates are **not** forced to stay silent: nothing forbids a withdrawal keyed by a losing effect script in the same transaction. Guarding against an illegitimate claim of victory is each effect script's own job via `am_i_the_winner` (§4.19).

### 4.16 Vote: Mint (vote side)

| | |
| --- | --- |
| **Inputs** | A stake input under the stake policy (spent, consumed with `VoteProposal { proposal_id: p_id, voted_option }`). The proposal (reference input) under the proposal policy. |
| **Mint** | Exactly one token under the vote policy, name = hash of the stake input's reference, quantity `1`. |
| **Outputs** | One vote artifact at `out_idx`: address `Script(vote_policy)`, value holds the NFT and lovelace, inline datum, no reference script. |
| **Datum** | `VoteDatum { stake_owner: owner, proposal: p_id, voted_option, stake }` (`owner` from the stake datum, `stake` = the staked amount). |
| **Redeemer** | mint `MintVote { out_idx }`. |
| **Constraint** | The proposal is `Voting`; `0 <= voted_option < len(results)`. |

### 4.17 Vote: Tally (vote side)

| | |
| --- | --- |
| **Inputs** | The vote artifact, and the proposal UTxO (spent, consumed with `TallyVotes`). The proposal input is located by its NFT among the spent inputs, and its payment credential must hash to `proposal_policy`. |
| **Mint** | The vote's NFT is burned. |
| **Redeemer** | `TallyVote`. |
| **Authorization** | None directly; delegated to the proposal's `TallyVotes`. |

### 4.18 Vote: Cancel

| | |
| --- | --- |
| **Inputs** | The vote artifact. |
| **Mint** | The vote's NFT is burned. |
| **Outputs** | No continuation; the vote's ada may go anywhere. |
| **Redeemer** | `Cancel`. |
| **Authorization** | `stake_owner` (the vote's recorded owner) satisfied. |

`Cancel` is valid **at any time** while the artifact exists as long as the artifact is not consumed by a tally in the same transaction. The tally's burned-count check (§4.14) forbids canceling a vote inside the transaction that counts it without it being counted, so a canceled vote can never influence a tally.

### 4.19 Effect: run (withdraw)

An effect script runs as a reward withdrawal (`withdraw-0`). The reference `poll_effect` checks `am_i_the_winner`: **exactly one** input carrying an NFT under `proposal_policy` **and** sitting at payment credential `Script(proposal_policy)` must be consumed with `EndProposal { winner: Some(own_hash) }`. The shape check defeats spoofed proposal UTxOs (right token, wrong address) and rejects transactions closing two polls at once; any other redeemer on that input (e.g. a mid-transition `TallyVotes`) also fails. Additional business logic composes with `and`.

`proposal_policy` is **pinned at compile time** on purpose: deriving it from transaction data would let anyone forge an approving poll under their own proposal. Effect scripts must therefore be parameterized per deployed proposal validator.

## 5. Determinism & time

### 5.1 Reading time from the validity range

Scripts cannot read a clock; they read the transaction's validity range. The DAO uses **both** bounds, choosing per action:

- **Lower bound** as `now` where an action anchors *itself* in time or requires time to have *passed*: `CreatePosition`/`CreateProposal` (anchor `start_time`), `Deposit`/`Withdraw`/`ClosePosition` (prune locks), `RejectDraft`, `EndVotingStage`, `EndProposal` (all "after deadline" checks).
- **Upper bound** where an action must occur *before* a deadline: `Cosign`, `AcceptDraft` (draft window), `TallyVotes` (tally window), `Vote` (voting window).

An "after" check `now >= deadline` on the lower bound is sound because the ledger guarantees `real_slot >= lower_bound`; a "before" check `upper <= deadline` means the transaction is only valid if included before the deadline. Both bounds are required finite wherever they are read.

### 5.2 Phase deadlines

All deadlines derive from the proposal's immutable `start_time` and `timing_config`:

```
draft_end = start_time + draft_length
voting_end = draft_end + voting_length
tally_end  = voting_end + tally_length
```

Cosign and accept require inclusion `<= draft_end`; reject requires `>= draft_end`; end-voting requires `>= voting_end`; voting (stake side) requires inclusion `<= voting_end`; tally requires `<= tally_end`; end-proposal requires `>= tally_end`.

### 5.3 Locks and frozen stake

A lock `(proposal_id, unlock_time, stake)` freezes the position's stake until `unlock_time`. The frozen amount is the **maximum** stake across all locks (the same tokens back every concurrent action); free stake is `total - frozen`. Locks are pruned when `unlock_time <= now` by `Deposit`, `Withdraw`, `ClosePosition`, and `Vote`. A lock also blocks a *second* cosign/vote on the same proposal via `has_proposal`. Creating a proposal is treated as locking until `start_time + draft_length` (the position can keep cosigning that proposal because `has_proposal` is checked on cosign, not create).

### 5.4 Strict-winner resolution

The winning option is the unique highest-voted option with a positive total; ties and zero votes yield no winner. Only a winner meeting the `execute` threshold resolves to its effect script; otherwise the poll closes with no execution.

## 6. Invariants

- **I1 — Action authorization.** Deposit/withdraw/delegate/close/create-proposal require the position `owner`; cosign/vote require `vote_auth` (delegatee if set, else owner); vote `Cancel` requires the vote's recorded `stake_owner`; proposal transitions require the corresponding sibling input consumed with the matching redeemer (which the sibling's own validator gates by authorization).
- **I2 — NFT uniqueness & custody.** Every position/proposal/vote NFT is named by the hash of a consumed output reference, so it is globally unique and unforgeable. Continuations keep the NFT at the exact script address; closing/burning is irreversible.
- **I3 — Lock enforcement.** Stake committed to a proposal is frozen (`free_stake` excludes the max live lock) until the lock expires; the same position cannot cosign/vote the same proposal twice while the lock is live.
- **I4 — Lifecycle integrity.** A proposal advances only in the order Draft → Voting → Tally, each transition gated by its deadline and threshold; the proposal body (`thresholds`, `timing_config`, `start_time`, `results`) is immutable across every transition.
- **I5 — Execution integrity.** `EndProposal`'s declared winner must equal the strict winner of the recorded tally, and executes only if the `execute` threshold is met; a declared effect must run as its withdrawal.
- **I6 — Vote fidelity.** A vote artifact records the exact staked amount and option at vote time, and is destroyed (NFT burned) exactly once, at tally or cancel; a proposal's tally counts only votes bound to it.
- **I7 — Composability.** Each validator asserts only about its own input, the sibling inputs/outputs it cross-references, the mint under its own policy, the single continuation it recognizes (by address or `out_idx`), the validity range, and the required authorization. It never asserts total input/output counts or unrelated value.

## 7. Threat model & known assumptions

### Defended

- **Unauthorized stake actions.** Deposit/withdraw/delegate/close/create are gated by the position `owner`; cosign/vote by `vote_auth`. (I1)
- **Double-voting / double-cosigning.** Locks freeze stake and `has_proposal` blocks a second cosign/vote on the same proposal. (I3)
- **Premature phase transitions.** Every transition is gated by its deadline via the validity range (lower for "after", upper for "before"); a proposal cannot be accepted/tallied/ended early. (I4)
- **Proposal tampering.** The proposal body is immutable across transitions; a continuation must reproduce it exactly. (I4)
- **Tally manipulation.** Votes are bound to a proposal and counted once each; the number of burned vote NFTs must match the votes counted; refunds go to the vote's recorded owner. The declared winner is checked against the tally, and the effect script self-guards via `am_i_the_winner`. (I5, I6)
- **NFT detachment / forgery.** NFT names hash a consumed reference (unique), and continuations must keep the NFT at the script address. (I2)

### Assumptions / out of scope

- **Settings authority is trusted.** The DAO reads its governance parameters and sibling hashes from the settings UTxO's `current` datum, located by its NFT. A party able to change settings can change thresholds/timings/sibling hashes. A malformed `current` fails the DAO closed (reject), never unsafely.
- **Create threshold is live; the rest are snapshotted.** `settings.thresholds.create` is read live at creation; `cosign`/`accept`/`vote`/`execute` and the timings are copied into the proposal at creation and frozen. Changing settings mid-lifecycle does not affect an already-created proposal.
- **One proposal tally per transaction.** `TallyVotes` requires the count of burned vote tokens to equal the votes counted for *this* proposal, which precludes tallying two proposals in one transaction (and precludes a `Cancel` burn inside a tallying transaction, §4.18).
- **One proposal per position lifetime.** The proposal NFT's name is the hash of the creating stake UTxO's reference (§3.5); since that reference is consumed once and can never be re-minted, a position can originate at most one proposal ever — even after all locks expire.
- **Continuation lookup is first-match.** Stake/proposal continuations are located as the first output at the spent input's address (§3.5). The validators do not assert output uniqueness at that address; an off-chain builder must never emit two contract outputs at the same script address in one transaction.
- **Vote cancellation has no deadline.** `Cancel` is authorized by the vote's recorded `stake_owner` at any time (§4.18), so a voter can retract a vote mid-voting — freeing the position's stake only at the lock's own expiry, not at cancel time.
- **Effect scripts are untrusted.** Being listed in `results` or having a withdrawal present proves nothing about the poll outcome; each candidate must verify its own victory via `am_i_the_winner`. The reference `poll_effect` does so; a deployer writing a real effect must reproduce this guard (and pin `proposal_policy` at compile time, §4.19).

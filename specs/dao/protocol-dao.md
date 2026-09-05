# DAO Protocol Specification

## 1. Summary

Token-based governance of a protocol and its treasury: token holders **stake** tokens into positions, **propose** actions, **vote** with weight proportional to their stake, and, if thresholds are met, a proposal resolves to an **effect** script that can execute the approved action.

The protocol is a set of three cooperating validators, each guarding its own single-NFT-threaded UTxO type, plus user-supplied per-option **effect** scripts:

- **`stake`** — a *stake position* UTxO holds a holder's staked tokens and records the locks that freeze them while a proposal is live. The validator's own hash is the stake-NFT policy id and the position address.
- **`proposal`** — a *proposal* UTxO carries a governance proposal through its lifecycle (Draft → Voting → Tally → closed). The validator's own hash is the proposal-NFT policy id and the proposal address.
- **`vote`** — a *vote artifact* UTxO records one holder's vote on one proposal and is destroyed at tally time. The validator's own hash is the vote-NFT policy id and the vote address.
- **Effect scripts** — the per-option validators a proposal references in its `results`. They are *not* part of the protocol; a proposal just names them, and the winning one runs under the withdraw-0 convention.

Governance parameters (thresholds, timings, and the sibling script hashes) are **not** compiled into the validators. They are read at runtime from a **settings UTxO** (see `specs/settings/protocol-settings.md`), located by its NFT via reference input, whose opaque `current` datum is cast to `DaoSettings`. This keeps the three DAO validators free of circular compile-time dependencies and lets the settings protocol govern the DAO's parameters.

The way it works is:

1. A holder **creates a stake position** by spending a wallet UTxO and minting its position NFT; ownership is established by proof-of-spend, and governance tokens deposited there weight everything that follows (§5.a).
2. The _owner_ **creates a proposal** once the position meets the `create` threshold; it starts in `Draft` and a lock freezes the position's stake until the draft deadline (§5.f).
3. Other holders **cosign** the draft, each adding their staked weight and taking their own lock (§5.g).
4. Once cosign stake reaches the `accept` threshold, anyone **accepts the draft**, promoting it to `Voting` (§5.h). If the deadline passes without acceptance, the draft is **rejected** and burned (§5.i).
5. During the voting window, holders **vote** on an option; each vote mints a vote artifact weighted by the position's stake, under a fresh lock (§5.j).
6. When voting ends, the proposal enters `Tally`, where votes are consumed in batches, their stakes counted per option, and their lovelace refunded (§5.l, §5.m).
7. After the tally deadline, `EndProposal` closes the poll: the **strict winner** is declared and, if it meets the `execute` threshold, its effect script runs as a reward withdrawal — otherwise the poll closes with nothing executed (§5.n, §5.o).
8. Throughout, positions can deposit, withdraw free stake, delegate, or cancel votes; a position closes only once all its locks have expired (§5.b–5.e, §5.k).

## 2. Design choices and limitations

### 2.a Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| State identity | **Three NFT-guarded UTxO types** | Stake, proposal, and vote each live in one UTxO identified by a token whose policy id *is* the validator's own hash. |
| NFT uniqueness | **Name = hash of a consumed `OutputReference`** | Hashing a spent output reference yields a globally unique, unforgeable token name, so every position/proposal/vote is unique by construction. |
| Governance params | **Read from a settings UTxO at runtime** | Avoids cyclic compile-time parameterization and lets the settings protocol govern the DAO. |
| Double-vote prevention | **Stake locks (freeze `max`, not sum)** | The same tokens back every concurrent action, so a position with `N` tokens can lend all `N` to several proposals at once; the frozen amount is the *maximum* committed stake across live locks. |
| Lifecycle | **Immutable proposal body, evolving `status`** | `thresholds`, `timing_config`, `start_time`, and `results` are locked at creation; only `status` evolves. |
| Execution | **`results`-bound effect scripts, withdraw-0** | A proposal binds each option to a script hash; the winner runs as a reward withdrawal and must verify its own victory via `am_i_the_winner`. |
| Authorization | **Pluggable `Credential`** | `owner`/`delegatee` are `Credential`s, so keys, multisigs, DAOs, or smart wallets can hold, propose, cosign, and vote. |

### 2.b Limitations

- **One proposal tally per transaction** — and no `Cancel` burn inside a tallying transaction (§5.m, §6.a).
- **Vote cancellation has no deadline** (§5.k, §6.a).
- **Create threshold is live; the other thresholds and timings are snapshotted** into the proposal at creation (§6.a).

## 3. Glossary

### 3.a Roles

- **Owner** (a `Credential` in a stake position): deposits, withdraws, delegates, closes the position, and creates proposals. Authorizes by key signature or by script invocation (withdraw-0).
- **Delegatee** (optional `Credential` in a stake position): when set, authorizes cosigning and voting on behalf of the position. The owner remains in control of deposits/withdrawals/closing/delegation/creation.
- **Proposer / Cosigner / Voter**: any holder of a sufficiently-staked position performing those actions.
- **Settings authority**: the party (or parties) able to change the `DaoSettings` via the settings protocol. The DAO validators trust that the settings UTxO's `current` datum, located by its NFT, is a well-formed `DaoSettings`.
- **Effect (poll) scripts**: per-option validators referenced by a proposal's `results`. Each must independently prove it is the winner of a legitimately-closed poll; the protocol does not trust them to be well-behaved.
- **Consumers**: contracts or parties that read proposal/settings state via reference inputs, or that run effect scripts.

### 3.b Constants

Baked into each script hash (all four are parameterized):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `staked_token_policy` | `PolicyId` | Policy of the governance token. |
| `staked_token_name` | `AssetName` | Name of the governance token. |
| `settings_policy` | `PolicyId` | Policy of the settings NFT (the settings script's own hash). |
| `settings_token_name` | `AssetName` | Name of the settings NFT. |
| `proposal_policy` | `PolicyId` | (effect scripts only) The proposal validator's own hash, pinned at compile time. |

The `stake`, `proposal`, and `vote` validators share the first four parameters. The `poll_effect` reference effect is parameterized only by `proposal_policy`.

Threshold and timing types (values live in the settings UTxO, §4.a):

```aiken
ProposalThresholds    = { create, cosign, accept, vote, execute : Int }
ProposalTimingConfig  = { draft_length, voting_length, tally_length : Int }
```

All deadlines derive from the proposal's immutable `start_time` and `timing_config`:

```
draft_end = start_time + draft_length
voting_end = draft_end + voting_length
tally_end  = voting_end + tally_length
```

Cosign and accept require inclusion `<= draft_end`; reject requires `>= draft_end`; end-voting requires `>= voting_end`; voting requires inclusion `<= voting_end`; tally requires `<= tally_end`; end-proposal requires `>= tally_end`. Each transaction's **Validity range** row (§5) states which bound it reads.

### 3.c Tokens

| Token | Policy | Name | Held by |
| --- | --- | --- | --- |
| Governance token | `staked_token_policy` | `staked_token_name` | Stake positions (the staked quantity weights votes and thresholds). |
| Stake NFT | stake validator hash | `blake2b_256(serialise(owner_utxo))` | The stake position UTxO. |
| Proposal NFT | proposal validator hash | hash of the creating stake UTxO's reference | The proposal UTxO. |
| Vote NFT | vote validator hash | hash of the voting stake UTxO's reference | The vote artifact UTxO. |
| Settings NFT | `settings_policy` | `settings_token_name` | The settings UTxO (§4.a). |

- **Naming rule.** A token name is `blake2b_256(serialise(<OutputReference>))`: hashing a *consumed* output reference yields a globally unique, unforgeable name.
- **Uniqueness consequences.** Because the reference is consumed once, it can never be minted again: every proposal and vote NFT name is globally unique and unforgeable.
- **NFT-quantity strictness.** Proposal, stake and vote continuation/creation outputs must hold **exactly one** own-policy NFT.

### 3.d Validators

Each validator's **own hash is its NFT policy id and its address payment credential**: `Script(policy)`.

**`stake`** — guards a stake position UTxO.

- mint (`StakePositionTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `CreatePosition { owner_utxo, out_idx }` | Mint a position NFT; create the position UTxO. |
| `CloseStakePosition` | Mint side of closing: burn exactly one position NFT. |

- spend (`StakeRedeemer`):

| Redeemer | Action |
| --- | --- |
| `Deposit` | Owner adds stake (or prunes locks). |
| `DelegateTo { delegatee: Option<Credential> }` | Owner sets, changes, or clears (`None`) the delegatee. |
| `Withdraw { amount }` | Owner withdraws free stake. |
| `ClosePosition` | Owner closes the position (all locks expired). |
| `CreateProposal` | Owner creates a proposal (records a lock). |
| `CosignProposal { proposal_id }` | Cosign a draft proposal (records a lock). |
| `VoteProposal { proposal_id, voted_option }` | Vote on a proposal (records a lock). |

**`proposal`** — guards a proposal UTxO through its lifecycle.

- mint (`ProposalTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `MintProposal { results, out_idx }` | Mint a proposal NFT; create the proposal UTxO. |
| `BurnProposal` | Mint side of reject/end: burn proposal NFTs. Admits **batch burns** so `RejectDraft` and `EndProposal` share one endpoint. |

- spend (`ProposalRedeemer`):

| Redeemer | Action |
| --- | --- |
| `Cosign` | Add a cosignature's stake to a draft. |
| `AcceptDraft` | Promote Draft → Voting once the accept threshold is met. |
| `RejectDraft` | Destroy a draft after its deadline. |
| `EndVotingStage` | Promote Voting → Tally after the voting deadline. |
| `TallyVotes` | Consume and count votes during the tally window. |
| `EndProposal { winner }` | Close the poll after the tally deadline; declare the winner. |

**`vote`** — guards a vote artifact UTxO.

- mint (`VoteTokenRedeemer`):

| Redeemer | Action |
| --- | --- |
| `MintVote { out_idx }` | Mint a vote NFT; create the vote artifact UTxO. |
| `BurnVotes` | Mint side of tally/cancel: burn vote NFTs. |

- spend (`VoteRedeemer`):

| Redeemer | Action |
| --- | --- |
| `TallyVote` | Consume a vote as part of tallying its proposal. |
| `Cancel` | Owner cancels the vote before tally (burns its NFT). |

**Effect scripts** (`poll_effect` reference): a `withdraw` endpoint under the withdraw-0 convention whose redeemer is entirely private to the script (`Data` in the reference). The protocol never inspects it.

## 4. UTxOs

Each validator's UTxO sits at an address whose payment credential is `Script(policy)` where `policy` is the validator's own hash. Continuation outputs are located by **address** (equal to the spent input's address) for stake/proposal; by explicit `out_idx` for the mint-created outputs. Inline datums and no reference script are required throughout.

### 4.a Settings UTxO

Each DAO action resolves the settings UTxO — the reference input holding `settings_token_name` under `settings_policy` — and casts its inline datum's `current` field (an opaque `Data` in the settings contract) to:

| Field | Type | Meaning |
| --- | --- | --- |
| `thresholds` | `ProposalThresholds` | Governance thresholds (in staked-token units). |
| `timings` | `ProposalTimingConfig` | Phase durations (POSIX milliseconds). |
| `stake_validator` | `ScriptHash` | Stake validator hash (also the stake-NFT policy id). |
| `proposal_validator` | `ScriptHash` | Proposal validator hash (also the proposal-NFT policy id). |
| `vote_validator` | `ScriptHash` | Vote validator hash (also the vote-NFT policy id). |

The cast is a hard `expect`: if the settings `current` datum is not a `DaoSettings`, the DAO action fails closed (rejected), never unsafely.

### 4.b Stake Position UTxO

Address `Script(stake_policy)`; value = one stake NFT + staked tokens + lovelace.

Datum (inline, on the stake address):

| Field | Type | Meaning |
| --- | --- | --- |
| `owner` | `Credential` | Who may deposit/withdraw/delegate/close/create. |
| `delegatee` | `Option<Credential>` | If set, who may cosign/vote on this position. |
| `locks` | `List<Lock>` | Live locks freezing stake; `Lock { proposal_id: ByteArray, unlock_time: Int, stake: Int }`. |

The **frozen** stake of a position is `max(lock.stake)` over all locks (0 when empty); the **free** stake is `total - frozen`. A lock is **expired** when `unlock_time <= now`; expired locks are dropped by `prune_expired`.

Locks are pruned when `unlock_time <= now` by `Deposit`, `Withdraw`, `ClosePosition`, and `Vote`. A lock also blocks a *second* cosign/vote on the same proposal via `has_proposal`. Creating a proposal is treated as locking until `start_time + draft_length`.

### 4.c Proposal UTxO

Address `Script(proposal_policy)`; value holds the proposal NFT and nothing extra.

Datum (inline, on the proposal address):

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

The transition graph (see §5 for exact per-action conditions):

```
                 Cosign (accumulate)                    AcceptDraft
Draft ──────────────────────────────► Draft ─────────────► Voting
                                        │                    │
       RejectDraft (burn) ◄─────────────┘                    │ EndVotingStage
                                                             ▼
                                        Tally ◄──────────────┘
                                          │
                                          ├── TallyVotes (accumulate)
                                          └── EndProposal (burn + execute winner)

```

### 4.d Vote Artifact UTxO

Address `Script(vote_policy)`; value holds the vote NFT and lovelace.

Datum (inline, on the vote address):

| Field | Type | Meaning |
| --- | --- | --- |
| `stake_owner` | `Credential` | The stake position's `owner` at vote time (who may `Cancel`). |
| `proposal` | `ByteArray` | The proposal token name the vote belongs to. |
| `voted_option` | `Int` | Index into the proposal's `results`. |
| `stake` | `Int` | The staked amount that weights this vote at tally. |

The artifact is destroyed exactly once, either at tally time (§5.m) or by cancellation (§5.k).

## 5. Transactions

All possible protocol transactions. Each section below describes one complete, atomic transaction: **5.x.a Scripts executed** names every validator instance the transaction runs (validator, purpose, and redeemer), and **5.x.b Transaction** describes the transaction as a whole, rather than a per-script fraction. When a check belongs to one validator only, the constraints row labels it; otherwise it holds for the transaction as a whole.

Every transaction also resolves the settings UTxO — the reference input holding the settings NFT (§4.a) — to read thresholds, timings, and sibling hashes; it is omitted from the tables for brevity. "The own input" is the contract UTxO being spent; cross-references to sibling inputs/outputs are checked locally and each sibling's own validator re-checks its detailed constraints.

Scripts read the transaction's validity range. The **lower bound** is read as `now` where an action anchors *itself* in time or requires time to have *passed* (creating, pruning locks, "after deadline" checks); the **upper bound** is used where an action must occur *before* a deadline. An "after" check `now >= deadline` on the lower bound is sound because the ledger guarantees `real_slot >= lower_bound`; a "before" check `upper <= deadline` means the transaction is only valid if included before the deadline. Both bounds are required finite wherever they are read; each transaction's **Validity range** row below states which bound it reads.

### 5.a Create Position

A holder turns a wallet UTxO into a stake position: the position NFT is minted, the position UTxO is created at the stake address, and ownership is established by proof-of-spend of the `owner_utxo`.

#### 5.a.a Scripts executed

- Stake validator with mint purpose and `CreatePosition { owner_utxo, out_idx }` redeemer.

#### 5.a.b Transaction

| | |
| --- | --- |
| **Inputs** | The `owner_utxo` (must be spent). Any wallet UTxOs funding the staked tokens. |
| **Mint** | Exactly one token under the stake policy, name = hash of `owner_utxo`, quantity `1`. |
| **Outputs** | One position at `out_idx`: address `Script(stake_policy)`, value = NFT + ≥ 1 staked token + lovelace (exactly three assets), inline datum `StakePositionDatum { owner: payment_credential(owner_utxo), delegatee: None, locks: [] }`, no reference script. |
| **Validity range** | Unconstrained. |
| **Authorization** | None. The owner is the payment credential of the consumed `owner_utxo`; ownership is established by proof-of-spend, not a signature. |

### 5.b Deposit

The owner adds governance tokens to the position (or merely prunes its expired locks); the position continues at the same address.

#### 5.b.a Scripts executed

- Stake validator with spend purpose and `Deposit` redeemer.

#### 5.b.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(locks, now)`, staked token `>=` the spent amount, NFT quantity `1`, exactly three assets. |
| **Validity range** | Lower bound finite (`now`). |
| **Authorization** | `owner` satisfied. |

### 5.c Delegate

The owner sets, changes, or clears the position's delegatee; locks and value pass through untouched.

#### 5.c.a Scripts executed

- Stake validator with spend purpose and `DelegateTo { delegatee }` redeemer.

#### 5.c.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner unchanged, `delegatee = delegatee` (set, changed, or cleared with `None`), `locks` unchanged (not pruned). |
| **Validity range** | Unconstrained. |
| **Authorization** | `owner` satisfied. |

### 5.d Withdraw

The owner withdraws free stake — total minus the maximum live lock — from the position; the withdrawn amount may go anywhere.

#### 5.d.a Scripts executed

- Stake validator with spend purpose and `Withdraw { amount }` redeemer.

#### 5.d.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Outputs** | One continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(locks, now)`, staked token `= in_stake - amount`, NFT quantity `1`, exactly three assets. The withdrawn amount may go anywhere. |
| **Validity range** | Lower bound finite (`now`). |
| **Authorization** | `owner` satisfied. |
| **Constraints** | `0 <= amount <= free_stake(in_stake, prune_expired(locks, now))`. |

### 5.e Close Position

The owner closes the position once all its locks have expired: the position NFT is burned and the remaining stake/ada may go anywhere.

#### 5.e.a Scripts executed

- Stake validator with spend purpose and `ClosePosition` redeemer.
- Stake validator with mint purpose and `CloseStakePosition` redeemer.

#### 5.e.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Mint** | The position NFT is burned (quantity `-1`). |
| **Outputs** | No continuation required; remaining stake/ada may go anywhere. |
| **Validity range** | Lower bound finite (`now`); **all locks must be expired** (`prune_expired(locks, now) == []`). |
| **Authorization** | `owner` satisfied. |

### 5.f Create Proposal

The owner commits the position's stake to a new proposal: a lock freezes the stake until the draft deadline, and a fresh proposal UTxO starts in `Draft` weighted by the position's stake, its NFT named after the position's spent reference.

#### 5.f.a Scripts executed

- Stake validator with spend purpose and `CreateProposal` redeemer.
- Proposal validator with mint purpose and `MintProposal { results, out_idx }` redeemer.

#### 5.f.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Mint** | Exactly one proposal NFT under `proposal_validator`, name = hash of this position's reference, quantity `1`. |
| **Outputs** | 1. One position continuation at the same address: owner/delegatee unchanged, `locks = push(locks, Lock { proposal_id, now + draft_length, in_stake })`. 2. One proposal at `out_idx`: address `Script(proposal_policy)`, value holds the NFT and nothing extra, inline datum `ProposalDatum { thresholds: settings.thresholds, timing_config: settings.timings, start_time: now, status: Draft { cosigning_stake: staked_amount }, results }`, no reference script. |
| **Validity range** | Lower bound finite (`now` = proposal `start_time`). |
| **Authorization** | The position `owner` on the stake spend; the proposal mint has none directly — it requires the stake input to be consumed with `CreateProposal`. |
| **Constraints** | `in_stake = staked_amount >= settings.thresholds.create` (checked by both validators). |

### 5.g Cosign

Another holder commits their position's stake to a draft proposal: the proposal's cosigning stake grows and the cosigning position takes its own lock until the draft deadline.

#### 5.g.a Scripts executed

- Proposal validator with spend purpose and `Cosign` redeemer.
- Stake validator with spend purpose and `CosignProposal { proposal_id }` redeemer.

#### 5.g.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO, and the cosigning position UTxO. |
| **Outputs** | 1. One proposal continuation at the same address with status `Draft { cosigning_stake: n + s }` (`s` = the cosigner's staked amount); immutables preserved. 2. One position continuation at the same address: owner/delegatee unchanged, `locks = concat(locks, [Lock { proposal_id, proposal.start_time + proposal.draft_length, in_stake }])`. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length` (enforced by the proposal validator; the stake side reads no bound). |
| **Authorization** | `vote_auth` (delegatee if set, else owner) on the stake spend; the proposal spend has none directly — it requires the stake input consumed with `CosignProposal { proposal_id }`. |
| **Constraints** | (proposal) Status is `Draft { cosigning_stake: n }`. (stake) The proposal is `Draft`; `in_stake >= proposal.thresholds.cosign`; the position has no lock for `proposal_id` (`!has_proposal`). |

### 5.h Accept Draft

Once the accumulated cosign stake reaches the accept threshold, anyone can promote the draft to `Voting`.

#### 5.h.a Scripts executed

- Proposal validator with spend purpose and `AcceptDraft` redeemer.

#### 5.h.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Outputs** | One continuation at the same address with status `Voting`; immutables preserved. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length`. |
| **Constraints** | Status `Draft { cosigning_stake: n }` with `n >= thresholds.accept`. |

### 5.i Reject Draft

After the draft deadline, anyone can reject an unaccepted draft: the proposal NFT is burned and the poll never happens.

#### 5.i.a Scripts executed

- Proposal validator with spend purpose and `RejectDraft` redeemer.
- Proposal validator with mint purpose and `BurnProposal` redeemer.

#### 5.i.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Mint** | The proposal NFT is burned. |
| **Outputs** | No continuation. |
| **Validity range** | Lower bound finite and `>= start_time + draft_length`. |
| **Constraints** | Status `Draft`. |

### 5.j Vote

A position casts its staked weight on one option of a `Voting` proposal: a vote artifact is minted — named after the position's spent reference, recording the owner, option, and exact staked amount — and the stake is locked until the voting deadline.

#### 5.j.a Scripts executed

- Stake validator with spend purpose and `VoteProposal { proposal_id, voted_option }` redeemer.
- Vote validator with mint purpose and `MintVote { out_idx }` redeemer.

#### 5.j.b Transaction

| | |
| --- | --- |
| **Inputs** | The position UTxO. |
| **Reference inputs** | The proposal UTxO. |
| **Mint** | Exactly one vote NFT under `vote_validator`, name = hash of the position's reference, quantity `1`. |
| **Outputs** | 1. One position continuation at the same address: owner/delegatee unchanged, `locks = prune_expired(concat(locks, [Lock { proposal_id, start + draft + voting, in_stake }]), now)`. 2. One vote artifact at `out_idx`: address `Script(vote_policy)`, value holds the NFT and lovelace, inline datum `VoteDatum { stake_owner: owner, proposal: p_id, voted_option, stake }` (`owner` from the stake datum, `stake` = the staked amount), no reference script. |
| **Validity range** | Lower and upper bounds finite; `upper <= start + draft + voting` (enforced by the stake validator). |
| **Authorization** | `vote_auth` (delegatee if set, else owner) on the stake spend; the vote mint has none directly — it requires the stake input consumed with `VoteProposal { proposal_id: p_id, voted_option }`. |
| **Constraints** | The proposal is `Voting`; `in_stake >= proposal.thresholds.vote`; no existing lock for `proposal_id`; `0 <= voted_option < len(results)` (checked by the vote mint; the stake side ignores `voted_option`). |

### 5.k Cancel Vote

The vote's recorded owner can cancel the artifact at any time, burning its NFT; the position's stake is freed only when the lock itself expires.

#### 5.k.a Scripts executed

- Vote validator with spend purpose and `Cancel` redeemer.
- Vote validator with mint purpose and `BurnVotes` redeemer.

#### 5.k.b Transaction

| | |
| --- | --- |
| **Inputs** | The vote artifact. |
| **Mint** | The vote's NFT is burned. |
| **Outputs** | No continuation; the vote's ada may go anywhere. |
| **Validity range** | Unconstrained. |
| **Authorization** | `stake_owner` (the vote's recorded owner) satisfied. |

`Cancel` is valid **at any time** while the artifact exists as long as the artifact is not consumed by a tally in the same transaction. The tally's burned-count check (§5.m) forbids canceling a vote inside the transaction that counts it without it being counted, so a canceled vote can never influence a tally.

### 5.l End Voting Stage

After the voting deadline, anyone can freeze the poll into `Tally` with zeroed counters, ready to accumulate vote totals.

#### 5.l.a Scripts executed

- Proposal validator with spend purpose and `EndVotingStage` redeemer.

#### 5.l.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Outputs** | One continuation at the same address with status `Tally { votes: [0 × len(results)] }`; immutables preserved. |
| **Validity range** | Lower bound finite and `>= start_time + draft_length + voting_length`. |
| **Constraints** | Status `Voting`. |

### 5.m Tally

One or more vote artifacts are consumed in a batch: their stakes are added to the per-option totals, their NFTs are burned, and their lovelace is refunded to their recorded owners.

#### 5.m.a Scripts executed

- Proposal validator with spend purpose and `TallyVotes` redeemer.
- Vote validator with spend purpose and `TallyVote` redeemer (one per consumed vote).

#### 5.m.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO, plus one or more vote UTxOs (each spent with `TallyVote`). |
| **Mint** | Each consumed vote's NFT is burned (quantity `-1` under the vote policy). |
| **Outputs** | 1. One proposal continuation at the same address with status `Tally { votes: counted }`; immutables preserved. 2. Per consumed vote, a refund to an output whose payment credential is its `stake_owner`, holding **at least** the vote UTxO's lovelace. |
| **Validity range** | Upper bound finite and `<= start_time + draft_length + voting_length + tally_length` (enforced by the proposal validator). |
| **Constraints** | (proposal) Status `Tally { votes }`; at least one vote consumed; the number of burned vote tokens equals the number of votes counted for *this* proposal. (vote, each) The proposal input is located by its NFT among the spent inputs, and its payment credential must hash to `proposal_policy`. |

Votes whose recorded `voted_option` falls outside `0 .. len(results) - 1` are consumed and burned but their stake is **silently dropped** from the tally. `MintVote` already rejects such options, so this is defense in depth against hand-forged artifacts.

### 5.n End Proposal

After the tally deadline the poll closes: the strict winner is declared, the proposal NFT is burned, and — if the `execute` threshold is met — the winning effect script runs as a reward withdrawal.

#### 5.n.a Scripts executed

- Proposal validator with spend purpose and `EndProposal { winner }` redeemer.
- Proposal validator with mint purpose and `BurnProposal` redeemer.
- (If `winner = Some(effect)`.) Effect script with withdraw purpose (`withdraw-0`), §5.o.

#### 5.n.b Transaction

| | |
| --- | --- |
| **Inputs** | The proposal UTxO. |
| **Mint** | The proposal NFT is burned (quantity `-1`). |
| **Outputs** | No continuation. |
| **Withdrawals** | If `winner = Some(effect)`, a withdrawal keyed by `Script(effect)` must be present (the effect runs). |
| **Validity range** | Lower bound finite and `>= start_time + draft_length + voting_length + tally_length`. |
| **Constraints** | `winner` must equal the expected value exactly: the **strict winner** of `votes` (a unique option with the highest total and no tie, total `> 0`); if that total is `>= thresholds.execute`, the expected effect is `results[option]`, otherwise `None` (no outcome qualifies for execution). Ties and zero votes yield no winner. |

Losing candidates are **not** forced to stay silent: nothing forbids a withdrawal keyed by a losing effect script in the same transaction. Guarding against an illegitimate claim of victory is each effect script's own job via `am_i_the_winner` (§5.o).

### 5.o Run Effect

The same transaction as End Proposal (§5.n), from the effect script's point of view: an effect script runs as a reward withdrawal (`withdraw-0`). The reference candidate script `poll_effect` checks `am_i_the_winner`: **exactly one** input carrying an NFT under `proposal_policy` **and** sitting at payment credential `Script(proposal_policy)` must be consumed with `EndProposal { winner: Some(own_hash) }`. The shape check defeats spoofed proposal UTxOs (right token, wrong address) and rejects transactions closing two polls at once; any other redeemer on that input (e.g. a mid-transition `TallyVotes`) also fails. Additional business logic composes with `and`.

`proposal_policy` is **pinned at compile time** on purpose: deriving it from transaction data would let anyone forge an approving poll under their own proposal. Effect scripts must therefore be parameterized per deployed proposal validator.

## 6. Threat model

### Defended

- **Unauthorized stake actions.** Deposit/withdraw/delegate/close/create are gated by the position `owner`; cosign/vote by `vote_auth`. (I1)
- **Double-voting / double-cosigning.** Locks freeze stake and `has_proposal` blocks a second cosign/vote on the same proposal. (I3)
- **Premature phase transitions.** Every transition is gated by its deadline via the validity range (lower for "after", upper for "before"); a proposal cannot be accepted/tallied/ended early. (I4)
- **Proposal tampering.** The proposal body is immutable across transitions; a continuation must reproduce it exactly. (I4)
- **Tally manipulation.** Votes are bound to a proposal and counted once each; the number of burned vote NFTs must match the votes counted; refunds go to the vote's recorded owner. The declared winner is checked against the tally, and the effect script self-guards via `am_i_the_winner`. (I5, I6)
- **NFT detachment / forgery.** NFT names hash a consumed reference (unique), and continuations must keep the NFT at the script address. (I2)

### 6.a Assumptions

- **Settings authority is trusted.** The DAO reads its governance parameters and sibling hashes from the settings UTxO's `current` datum, located by its NFT. A party able to change settings can change thresholds/timings/sibling hashes. A malformed `current` fails the DAO closed (reject), never unsafely.
- **Create threshold is live; the rest are snapshotted.** `settings.thresholds.create` is read live at creation; `cosign`/`accept`/`vote`/`execute` and the timings are copied into the proposal at creation and frozen. Changing settings mid-lifecycle does not affect an already-created proposal.
- **One proposal tally per transaction.** `TallyVotes` requires the count of burned vote tokens to equal the votes counted for *this* proposal, which precludes tallying two proposals in one transaction (and precludes a `Cancel` burn inside a tallying transaction, §5.k).
- **Vote cancellation has no deadline.** `Cancel` is authorized by the vote's recorded `stake_owner` at any time (§5.k), so a voter can retract a vote mid-voting — freeing the position's stake only at the lock's own expiry, not at cancel time.
- **Effect scripts are untrusted.** Being listed in `results` or having a withdrawal present proves nothing about the poll outcome; each candidate must verify its own victory via `am_i_the_winner`. The reference `poll_effect` does so; a deployer writing a real effect must reproduce this guard (and pin `proposal_policy` at compile time, §5.o).

### 6.b Invariants

- **I1 — Action authorization.** Deposit/withdraw/delegate/close/create-proposal require the position `owner`; cosign/vote require `vote_auth` (delegatee if set, else owner); vote `Cancel` requires the vote's recorded `stake_owner`; proposal transitions require the corresponding sibling input consumed with the matching redeemer (which the sibling's own validator gates by authorization).
- **I2 — NFT uniqueness & custody.** Every position/proposal/vote NFT is named by the hash of a consumed output reference, so it is globally unique and unforgeable. Continuations keep the NFT at the exact script address; closing/burning is irreversible.
- **I3 — Lock enforcement.** Stake committed to a proposal is frozen (`free_stake` excludes the max live lock) until the lock expires; the same position cannot cosign/vote the same proposal twice while the lock is live.
- **I4 — Lifecycle integrity.** A proposal advances only in the order Draft → Voting → Tally, each transition gated by its deadline and threshold; the proposal body (`thresholds`, `timing_config`, `start_time`, `results`) is immutable across every transition.
- **I5 — Execution integrity.** `EndProposal`'s declared winner must equal the strict winner of the recorded tally, and executes only if the `execute` threshold is met; a declared effect must run as its withdrawal.
- **I6 — Vote fidelity.** A vote artifact records the exact staked amount and option at vote time, and is destroyed (NFT burned) exactly once, at tally or cancel; a proposal's tally counts only votes bound to it.
- **I7 — Composability.** Each validator asserts only about its own input, the sibling inputs/outputs it cross-references, the mint under its own policy, the single continuation it recognizes (by address or `out_idx`), the validity range, and the required authorization. It never asserts total input/output counts or unrelated value.

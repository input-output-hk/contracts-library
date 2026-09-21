# Event-Triggered Assets — Tokenized Bond Specification

## 1. Summary

A **tokenized bond** is a CIP-113 programmable token that records a fixed schedule of value and settles into a plain native token at maturity. One transaction **registers** the CIP-113 instance and **issues** the first tokens to the beneficiary, publishing the bond's terms as a CIP-68 reference datum (§4.1). The principal then moves **freely** — no transfer rule gates who may hold or send it at any point of its life (§4.2). At each deadline the bond's value steps up 4%: the **reference token's** datum is rewritten *in place*, holder-passively, with no signatures (§4.4). From the final deadline on, the owner **may** — never must — **graduate**: the programmable token burns and the plain native token is minted at the schedule's final value (§4.5).

Two postures make the instrument trustworthy:

- **Ownership rides the inline stake credential** of the token UTxO. It moves with the token at every transfer and is what the graduation binds the payout to. CIP-113 attributes ownership only by the *stake* credential — the native asset's *payment* (spending) key is not something the framework can tie to the owner, so it must come from the owner: named in an owner-signed graduation, or pre-committed to the token's datum on an owner-signed self-transfer (§4.3).
- **A graduation can never redirect a payout.** It runs exactly one spend chain — the owner-signed transfer path, or the permissionless third-party path (which only works for tokens whose owner opted in beforehand) — plus a shared burn. Absent an owner signature *and* a committed payment credential the transaction is rejected: a native asset sent to an unverified spending key is unrecoverable, so there is no fallback.

### Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| Custody | **CIP-113 programmable-logic base (PLB)** | All token UTxOs are custodied at the shared base; ownership is the token UTxO's inline stake credential, which rides the token and is what graduation binds the payout to. |
| Transfer | **Permissive `transfer_logic`, forever** | The transfer path never gates who may hold or send; the token is DEX/venue-compatible before and after every deadline (P1, Q-RULE-3). |
| Instrument state | **CIP-68 reference token under the same policy** | The mutable state (schedule, current value) lives in a CIP-68 `222` reference token custodied at the PLB and staked to the *transformation script*, so it can be updated in place without touching any holder's tokens (§4.4). |
| Schedule | **Baked validator constants, fixed-point** | Fixed 4% annual over four years, precomputed off-chain: `[(d1,v1) … (d4,v4)]` with `v4 ≈ 1.1699 × scale`. No on-chain compounding: the validator only looks the current value up by time. |
| Registration | **Atomic register + issue** | A single `RegisterAndMint` arm validates registration authority (issuer signature), node shape and the first-batch mint in one transaction (§4.1); no window between registering and holding tokens. |
| Transformation | **Holder-passive, permissionless** | No signatures: anyone may submit; the transformation script's withdraw-0 is the time gate. A late submission jumps straight to the current step (the new value is a pure lookup). |
| Payout key | **Opt-in, owner-signed self-transfer** | Only the owner can write a `payment_credential` into the token's datum; optional and re-settable (§4.3). |
| Graduation | **Opt-in, owner-authorized destination, no fallback** | Two spend paths (owner-signed; permissionless third-party for opted-in tokens), one shared burn (§4.5). Absent an owner signature and a committed destination the tx is rejected (Q-GRAD-2). |
| Graduated asset | **New native policy, burn-backed scaled mirror** | The native policy mints exactly `burned × v4 / scale`, approving only against the governed burn of the same name ("no burn CIP, no mint", scaled). Deliberately not 1:1 quantity-conserved (Q-GRAD-1). |
| Companion assets | **Fail closed** | Graduation burns the principal asset name only; any other governed name (the CIP-68 reference token or an unknown one) survives a conversion. |
| Third-party mechanics | **Ghost continuation, ratcheted** | The paired continuation preserves address, datum and reference script byte-for-byte; lovelace is ratcheted (`output ≥ input`). The ghost UTxO is one-time per spent UTxO and reclaimable by the owner via a transfer-path spend. |

## 2. Roles

- **Issuer**: parameterizes and registers the instance and gates the supply (the T0/T1 signature).
- **Owner / holder**: whoever the token UTxO's **inline stake credential** names. May transfer freely (§4.2), commit a payout key (§4.3), and graduate by signing (§4.5 owner path). An owner who intends to sign their own graduation never needs §4.3.
- **Beneficiary**: the initial owner named at issue (the §4.1 principal output's stake credential).
- **Transformation script**: a smart-wallet stake credential that owns the reference token; its withdraw-0 authorizes the in-place schedule update (§4.4) — the only mutation authority over bond state.
- **Payout payment credential**: the spending credential of the destination the native asset lands at (§4.5). It must be owner-supplied (named in an owner-signed graduation, or pre-committed via §4.3); the destination's stake credential stays bound to the owner's current credential.
- **Submitters**: §4.2/§4.3 — the owner (signature required). §4.4 — anyone, no signature (normally the issuer; the holder can force it). §4.5 — the owner (owner path) or any third party (third-party path; only for tokens whose owner opted in).
- **Core protocol** (trusted infrastructure, not part of this instrument): the PLB global validator, the core `transfer` / `third_party` stake validators (dispatch), the `issuance_mint` policy, and the registry mint/spend handlers.

## 3. State model

### 3.1 Ownership and custody

- Token UTxOs live at the programmable-logic base; **ownership = the UTxO's inline stake credential**. It moves with the token at every transfer.
- Minted tokens must land at PLB outputs with an inline stake credential and a **bounded inline datum** (the deployment's `max_inline_datum_bytes`); a UTxO born over the bound is frozen and unseizable. This is enforced by the core's `issuance_logic` (`no_escape`); the substandard does not re-check it, but builders must respect the bound or freeze the instrument.
- A transfer's continuation preserves the seizable output shape (inline stake credential, no reference script) and bounds the datum, so commitments written into the datum (§4.3) never freeze the token.

### 3.2 Principal token

| Field | Meaning |
| --- | --- |
| value | `cip_policy` × `N` — the principal supply, issuer-gated; two asset names under one policy (principal + reference), no per-holder state to mint against. |
| stake credential | Inline — the owner. Moves with the token at every transfer. |
| datum | Inline, optional — normally empty; after §4.3 optionally `{ payment_credential }`, the owner's pre-committed payout credential. Free for this purpose because the CIP-68 metadata lives on the reference token. |

### 3.3 Reference token (CIP-68 `222`)

One unit under the same `cip_policy`, custodied at the PLB with the **transformation script** as inline stake credential. Inline datum:

| Field | Meaning |
| --- | --- |
| `metadata` | `{ name, ticker, terms-url, … }` (CBOR) — CIP-68 publication for wallets and indexers. |
| `version` | `1`. |
| `extra` | `{ schedule: [(d1,v1) … (d4,v4)], value: v_k }` — the baked schedule and the current recorded value (`v0` at issue; stale values are harmless). |

The datum must stay within `max_inline_datum_bytes`: keep it to the schedule and value, heavy CIP-25-style blobs would freeze the UTxO.

### 3.4 RegistryNode

One node at the registry address holds the instance configuration:

| Field | Meaning |
| --- | --- |
| `key` / `next` | Linked-list keys; `key` is the governed policy id. |
| `minting_logic` | This substandard's mint/burn authority (the `RegisterAndMint` / `Burn` arm). |
| `transfer_logic` | The permissive transfer predicate (P1). |
| `third_party_logic` | The governed-extraction predicate (graduation-only in this instrument). |
| `unfracking_logic`, `global_state_cs` | `∅` — unused by this instrument. |

The node is **only ever referenced**, never spent, by instrument transactions (§6, I7).

### 3.5 Schedule

`d1 < d2 < d3 < d4` are the four annual deadlines; `v1 … v4` the corresponding values in fixed-point `scale` units (`v4 ≈ 1.1699 × scale`, 4% compounded). The values are baked as validator constants, precomputed off-chain; the CIP-68 reference datum mirrors them for wallets and indexers, and the graduation math reads the baked `v4`.

## 4. Transactions

Each section is one complete transaction; the normative diagrams are the `design.typ` figures of the same name. The withdraw-0s of a PLB spend are listed by role; the ledger presents withdrawals in its canonical order (scripts before vkeys, ascending), and builders derive every `wdrl_idx` of the `BaseSpendRedeemer { params_idx, wdrl_idx }` from the sorted set (09-DEVELOPING-SUBSTANDARDS §10).

### 4.1 Register + issue (T0/T1)

| | |
| --- | --- |
| **Inputs** | Issuer funds (wallet): `min_ada` + a fee asset `f`. |
| **Reference inputs** | Protocol params. |
| **Mint** | `registry_node_cs`: `1` (registry mint handler). `cip_policy`: `N` (principal) `+ 1` (reference `222`) — under the `issuance_mint` policy. |
| **Withdrawals** | `minting_logic` [RegisterAndMint] (0); core `issuance_logic` [names policy + OutputIndex proof] (0). |
| **Signatures** | Issuer. |
| **Outputs** | 1. **RegistryNode** at the registry address: `registry_node_cs` × 1 + `min_ada`, datum per §3.4. 2. **Principal tokens** at the PLB [stake: beneficiary]: `cip_policy` × `N`. 3. **Reference token** at the PLB [stake: transformation script]: `cip_policy` × 1, datum per §3.3 with `value: v0`. |
| **Validity range** | Unconstrained. |
| **Authorization** | Issuer signature. |
| **Constraints** | The single `RegisterAndMint` arm validates registration authority, node shape and the first-batch mint together, and cross-checks the transaction shape: the node NFT is minted → the node is created; the `cip_policy` entries are present in `tx.mint`. |

### 4.2 Free transfer (T2)

| | |
| --- | --- |
| **Inputs** | Principal tokens at the PLB [stake: sender], `cip_policy` × `N`, redeemer `BaseSpendRedeemer { params_idx, wdrl_idx }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] (0) → `transfer` [TransferRedeemer] (0) → `transfer_logic` (ours) (0). |
| **Signatures** | Sender (the spent UTxO's stake credential). |
| **Outputs** | Principal tokens at the PLB [stake: recipient], `cip_policy` × `N`. |
| **Validity range** | Unconstrained — valid at every point of the lifecycle, before and after the deadlines. |
| **Constraints** | The dispatcher selects the transfer path (`TransferAct`); the PLB spend redeemer carries no action arm. The permissive `transfer_logic` never gates who may hold or send. |

### 4.3 Register payout key (T2b)

A special case of §4.2: the owner transfers the token to themselves and writes a payment credential into its datum. This is the opt-in that lets someone else (typically the issuer) graduate the token later without being able to redirect the payout — only the owner, by signing this transfer, can set it.

| | |
| --- | --- |
| **Inputs** | Principal tokens at the PLB [stake: owner], `cip_policy` × `N`, redeemer `BaseSpendRedeemer { params_idx, wdrl_idx }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | As §4.2. |
| **Signatures** | Owner. |
| **Outputs** | Principal tokens at the PLB [stake: owner] (same address), `cip_policy` × `N`, datum `{ payment_credential: owner_payment_cred }`. |
| **Validity range** | Unconstrained. |
| **Constraints** | The only difference from an ordinary transfer is the output datum. Because the transfer is owner-signed (`authorised_stake_cred`), only the owner can set the commitment. The transfer path bounds the output datum (`max_inline_datum_bytes`) and preserves the seizable output shape, so the commitment does not freeze the token. Optional and re-settable: the owner may skip it (and sign the graduation directly) or overwrite it with a later self-transfer. |

### 4.4 Scheduled transformation (T3)

At each deadline `d_k` the bond's value steps up: the reference token's datum is rewritten *in place*.

| | |
| --- | --- |
| **Inputs** | Reference token at the PLB [stake: transformation script], `cip_policy` × 1, datum `{ metadata, version, extra: { schedule, value: v_{k-1} (stale is ok) } }`, redeemer `BaseSpendRedeemer { params_idx, wdrl_idx }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] (0) → `transfer` [TransferRedeemer] (0) → `transfer_logic` (ours) (0); `transformation_script` (ours) [time gate] (0). |
| **Signatures** | None. |
| **Outputs** | Reference token at the PLB [stake: transformation script], `cip_policy` × 1, datum `{ metadata, version, extra: { schedule, value: v_k = lookup(schedule, now) } }`. |
| **Validity range** | Lower bound finite, `≥ d_k`. |
| **Constraints** | In-place datum change on the *transfer path*: `authorised_stake_cred` accepts a script owner via its withdraw-0, which validates the schedule — the new value is a pure lookup of the baked constants, so a late submission jumps straight to the current step. The third-party path cannot do this: it preserves datums byte-for-byte. The principal tokens never move — only the instrument's recorded value changes. After `d4` the schedule is exhausted: the script rejects any further update and the value stops (the graduation window opens at `d4`, §4.5). |

### 4.5 Deadline graduation (T4)

From `d4` on, the tokens *may* convert into the corresponding native asset at the schedule's final value. Graduation is opt-in, never forced.

| | |
| --- | --- |
| **Inputs** | Principal tokens at the PLB [stake: holder], `cip_policy` × `N`, redeemer `BaseSpendRedeemer { params_idx, wdrl_idx }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−N` (burn, under the `issuance_mint` policy). `native_policy`: `N × v4 / scale` (the graduated asset). |
| **Withdrawals** | Exactly **one** spend chain, plus the shared burn — *owner path*: `programmable_logic_global` [TransferAct] (0) → `transfer` [TransferRedeemer] (0) → `transfer_logic` (ours) (0); *third-party path*: `programmable_logic_global` [ThirdPartyAct] (0) → `third_party` [ThirdPartyRedeemer] (0) → `third_party_logic` (ours) (0); *both paths*: `minting_logic` (ours) [Burn] (0) → core `issuance_logic` [names policy] (0). |
| **Signatures** | Owner path: the owner. Third-party path: none. |
| **Outputs** | 1. **Native asset** (wallet) at `owner_addr` [payment: owner-authorized, stake: owner]: `native_policy` × `N × v4 / scale`. 2. *Third-party path only:* **ghost continuation** at the PLB [stake: holder]: `min_ada` — the paired continuation preserves address, datum and reference script byte-for-byte, with lovelace ratcheted (`output ≥ input`). |
| **Validity range** | Lower bound finite, `≥ d4`. |
| **Constraints** | The Burn-mode validation is shared by both paths: burn shape; **full burn per asset name** (whole holdings burn, which makes per-owner destination attribution exact); destination binding; the scaled native mirror. Graduation burns the principal name only — any other governed name fails closed and survives. The native policy is signer-agnostic: it approves the mint only against the governed burn (`mint == burned × v4 / scale`), whichever credential signed. A burn fires `issuance_mint` with a negative quantity — the same two issuance withdraw-0s as a mint — plus the full spend chain of whichever action releases the tokens (09-DEVELOPING-SUBSTANDARDS §6). |

**Event gate (Q-RULE-1).** There is no separate rule script: the deadline check lives inside the substandard logic that already runs — the spend-side withdraw-0 (`third_party_logic` / `transfer_logic`) and the burn-side `minting_logic [Burn]` withdraw-0 — and approves iff the validity range reaches `d4` (time-driven, no oracle; the event condition is the transaction's own validity range).

**Authorization (Q-GRAD-2): the owner-authorized payout destination.** The `d4` event gate is necessary but not sufficient: the burn also needs a destination the owner authorized — *either* the owner's signature (owner path, which names the destination in the transaction) *or* a payment credential the owner pre-committed to the token datum (§4.3, preserved byte-for-byte through the third-party path, so a third party can complete the graduation but never redirect the payout). The permissionless third-party path therefore only works for tokens whose owners opted in beforehand. With no owner signature and no committed destination the transaction is rejected — graduation is optional, and the owner may hold the final-value, non-transforming token indefinitely.

**Base-layer guarantee.** A transaction that spends a registry node can never mint or burn that node's own token: graduation is pure issuance, never mixed with a registry reconfiguration (§6, I7).

## 5. Determinism & time

Scripts read the transaction's validity range; `now` is the **lower bound** (the ledger guarantees the real slot is ≥ it).

- §4.4 requires `now ≥ d_k`; since the new value is a pure lookup of the baked schedule, a late submission (`now ≥ d_{k+1}`) simply lands on the current step — staleness costs nothing.
- After `d4` the schedule is exhausted: §4.4 is rejected, and §4.5 becomes available with **no upper bound** — graduation stays opt-in forever.
- §4.1, §4.2 and §4.3 read no time bound.

## 6. Invariants

- **I1 — Ownership binding.** Ownership is the token UTxO's inline stake credential; it rides the token at every transfer, and graduation binds the payout to the owner's current credential (destination stake) with an owner-authorized payment credential.
- **I2 — Ungated transfer.** A transfer never gates who may hold or send; the permissive `transfer_logic` holds at every point of the lifecycle.
- **I3 — Seizable-shape and datum bounds.** Token continuations keep an inline stake credential, no reference script, and a datum within `max_inline_datum_bytes`; commitments (§4.3) never freeze the token, and UTxOs born over the bound are frozen and unseizable (builder responsibility).
- **I4 — Transformation integrity.** A §4.4 update is a pure time lookup of baked constants, gated by `now ≥ d_k`, applied only to the reference token under the transformation script's stake credential; the principal tokens never move.
- **I5 — Graduation integrity.** Graduation burns the principal name only (whole holdings per name), requires `now ≥ d4` **and** an owner-authorized payout destination, and mints exactly `burned × v4 / scale` under the native policy — backed by the governed burn ("no burn CIP, no mint"), regardless of which credential signed.
- **I6 — Ghost fidelity.** The third-party path's paired continuation preserves address, datum and reference script byte-for-byte, ratcheting lovelace (`output ≥ input`); the ghost is one-time per spent UTxO and reclaimable by the owner via a transfer-path spend. The owner path leaves nothing behind (the cheaper shape).
- **I7 — Pure issuance.** A transaction that spends a registry node can never mint or burn that node's own token: graduation is pure issuance, never mixed with a registry reconfiguration (base-layer guarantee; instrument transactions only *reference* the node).
- **I8 — Companion survival.** Other governed names under the policy (the CIP-68 reference token, or unknown ones) fail closed under a graduation burn and are never destroyed by a conversion.

## 7. Threat model & assumptions

### Defended

- **Payout redirection.** A graduation pays out only to an owner-authorized destination: the owner's signature, or the §4.3 pre-commitment preserved byte-for-byte through the third-party path, so a completer cannot redirect. Absent both, the transaction is rejected. (I5)
- **Unauthorized burn.** The `d4` gate plus the owner-authorized destination; whole-holdings-per-name burning keeps per-owner destination attribution exact. (I5)
- **Premature graduation or transformation.** Both are validity-range gated (`≥ d4`, `≥ d_k`) and there is no oracle to forge. (§5)
- **Schedule manipulation.** The schedule is baked as validator constants and the transformation is a pure lookup — no on-chain compounding to exploit. (I4)
- **Companion destruction.** Graduation burns the principal name only; companions fail closed. (I8)
- **Registry/issuance mixing.** Base-layer separation: a registry-node spend never co-occurs with that node's token mint/burn. (I7)
- **Over-minting the native asset.** The mint is burn-backed and scaled: the native policy approves only `burned × v4 / scale`, governed by the burn of the same name. (I5)

### Assumptions / out of scope

- **Submitter liveness is permissionless.** §4.4 needs no signatures, so the holder can force an update if the issuer stalls; §4.5's third-party path can be completed by anyone for opted-in tokens. No keeper is trusted.
- **`max_inline_datum_bytes` discipline.** Builders must keep datums within the deployment's bound; a UTxO born over it is frozen (harmless but lossy).
- **Ghost reclaim is the owner's transfer-path spend.** The property is guaranteed (I6); no dedicated transaction shape is specified.
- **Asset-identity continuity is open.** The native asset is a new policy (Q-GRAD-1): DEX pool / price-history continuity across the flip is a global open question, not solved per instrument.
- **Regulatory framing.** The library ships code only; whether a tokenized bond is a security in a given jurisdiction is the deployer's concern.

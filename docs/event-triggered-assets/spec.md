# Event-Triggered Assets — Tokenized Bond Specification

## 1. Summary

A **tokenized bond** backed by an ADA **vault**. The holder deposits the
principal into a vault (an ADA UTxO controlled by a company/country) and
receives a single CIP-113 **reference NFT** at the Programmable Logic Base
(PLB) that carries the instrument's published terms and its claim state. Over
the bond's life the holder claims **coupon tokens** (`cNt`) — one per scheduled
step — each of which is a plain native asset whose **asset name encodes the ADA
amount** it is worth. A `cNt` is redeemed by burning it at the vault: the vault
validator pays out exactly the ADA named by the burned coupons. At maturity the
holder claims a final `cNt` worth **only the principal** and retires the
reference NFT.

Two postures make the instrument legible:

- **The reference NFT is the certificate.** It lives at the PLB, is
  holder-staked (ownership = the UTxO's inline stake credential), holds the
  published terms and the last-claimed step, and moves with the claim: whoever
  holds it may claim the coupons still due. Its `step` anchor makes each coupon
  claimable exactly once.
- **Redemption is burn-to-pay.** A `cNt` is worth what its name says and only
  what its name says: the vault validator sums the amounts decoded from the
  burned coupon names and releases exactly that much ADA. The only residual
  trust is the vault owner's extraction path (§4.6) and the vault's solvency.

> This specification **replaces** the earlier single-NFT 1:1 graduation model.
> A single NFT still lives at the PLB — it is the reference NFT described here —
> but the economics now flow through the vault and the coupon tokens, not
> through a burn-and-mint of the certificate.

### Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| Principal | **ADA held in a vault** | The bond is backed by lovelace in a dedicated UTxO; no fungible principal token is minted into the float. |
| Vault control | **Owner extraction or burn-to-pay** | The company/country can extract (full custody); holders redeem by burning coupons. |
| Certificate | **Single CIP-113 reference NFT at the PLB** | One holder-staked token carries the terms and the claim state and moves with the claim. |
| Earnings | **`cNt` coupon tokens, amount in the name** | One native asset per step; the name is the amount, so the vault needs no external oracle or schedule. |
| Coupon claim | **Holder-signed, step-anchored** | The claim advances the reference NFT's `step`, so no step can be claimed twice. |
| Redemption | **Burn-to-pay at the vault** | Burning a coupon releases exactly `decode(name) × burned` ADA; double redemption is impossible (the coupon is destroyed). |
| Graduation | **Principal-only coupon at maturity** | A final `cNt` names the principal; the reference NFT is retired. |
| Trust | **Explicit full custody by the owner** | The owner-sign extraction path is unconditional and documented as the instrument's custody assumption. |

## 2. Roles

- **User / holder**: deposits the principal ADA into the vault and owns the
  reference NFT. Claims coupons and redeems them; may transfer the reference
  NFT, which transfers the right to future coupons and the principal claim.
- **Vault owner (company/country)**: holds the signing key that authorizes
  `OwnerExtract` — an unconditional custody path over the vault's ADA.
- **Issuer**: registers the instrument and mints the reference NFT; does not
  control coupons or the vault.
- **Vault**: an ADA UTxO with a small validator enforcing the two spend paths
  (§4.4, §4.6).
- **Coupon policy**: the minting policy of the `cNt` native assets (§4.3).
- **Core protocol** (trusted infrastructure): the CIP-113 PLB and the
  transfer / issuance validators that custody and move the reference NFT.

## 3. State model

### 3.1 Vault

An ADA UTxO that holds the instrument's principal plus the owner's own funds.
It is **pre-funded**: the holder's deposit sits alongside the owner's funds, so
coupon and principal redemptions are deterministically payable while the vault
is solvent. The vault is governed by a validator with two spend paths:

| Redeemer | Admitted when | Effect |
| --- | --- | --- |
| `OwnerExtract` | the owner's credential signs | The owner may move any ADA out of the vault (unconditional custody). |
| `Redeem` | no owner signature needed | The vault's net ADA loss equals the sum decoded from the burned coupons; the payout(s) go to the address(es) the redeemer names. |

The vault is a single UTxO (or a small set); a redemption spends it and
re-outputs the remainder. Solvency is an assumption, not an invariant (§7).

### 3.2 Coupon token (`cNt`)

A plain native asset under the **coupon policy**, with no CIP-113 custody. One
coupon is minted per scheduled step:

| Field | Meaning |
| --- | --- |
| policy id | The coupon policy's id. |
| asset name | The coupon's value **in lovelace, decimal**: name `"1124"` is worth `1124` lovelace. |
| quantity | `1` per claim (a coupon is a single claim unit). |

Because the name is only the amount, two coupons of equal amount are the same
asset (they are fungible with each other). This is intended: redeeming any unit
of `"1124"` pays `1124` lovelace, regardless of which step it came from.

### 3.3 Reference NFT (single CIP-113 token at the PLB)

The instrument's certificate and state anchor. Quantity `1`, custodied at the
PLB with the holder as its inline stake credential. Inline datum:

| Field | Meaning |
| --- | --- |
| `metadata` | `{ name, ticker, terms-url, … }` (CBOR) — publication for wallets and indexers. |
| `schedule` | `[(d1, amount1) … (d4, amount4)]` — the baked coupon schedule for reference. |
| `principal` | The ADA principal deposited into the vault (the graduation amount). |
| `step` | The number of the last coupon claimed (`0` at deposit); the claim anchor that makes each step claimable once. |

Ownership of the reference NFT is the claim: transferring it transfers the
remaining coupons and the principal claim. Its datum must stay within the
deployment's `max_inline_datum_bytes`.

### 3.4 Schedule

A non-empty, ascending sequence of `(deadline, amount)` steps, precomputed
off-chain. At each deadline `d_k` the holder may claim a coupon of `amount_k`
lovelace. The final deadline `d4` opens the graduation (principal) claim. The
schedule is recorded in the reference NFT's datum for wallets and indexers and
is enforced by the coupon policy's gating.

## 4. Transactions

Each section is one complete transaction. Withdrawals are listed by role; the
ledger presents them in its canonical order and builders derive indices from
the sorted set.

### 4.1 Register + deposit (T0)

The first transaction: the holder deposits the principal ADA into the vault and
the instrument mints the reference NFT to the holder.

| | |
| --- | --- |
| **Inputs** | User wallet funds: the principal ADA + `min_ada` + fees. |
| **Mint** | `cip_policy`: `1` (the reference NFT) — under the CIP-113 `issuance_mint` policy. `registry mint handler`: `1` (the RegistryNode). |
| **Outputs** | 1. **Vault**: its existing ADA **+ the deposited principal**, datum per §3.1. 2. **Reference NFT** at the PLB [stake: holder]: `cip_policy` × 1, datum `{ metadata, schedule, principal, step: 0 }`. 3. Change. |
| **Signatures** | Holder. |
| **Constraints** | The deposit into the vault and the reference-NFT mint happen atomically so the certificate and its backing exist together. The reference datum mirrors the schedule and records `step: 0`. |

### 4.2 Transfer the reference NFT (T1)

The reference NFT is a CIP-113 token at the PLB; moving it moves the claim.

| | |
| --- | --- |
| **Inputs** | Reference NFT at the PLB [stake: sender], `cip_policy` × 1. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] → `transfer` → `transfer_logic` (ours). |
| **Signatures** | Sender. |
| **Outputs** | Reference NFT at the PLB [stake: recipient], `cip_policy` × 1, datum preserved. |
| **Constraints** | The permissive transfer logic gates nothing; a plain transfer leaves the datum (including `step`) untouched. |

### 4.3 Coupon claim (step k, T-k)

At each deadline the holder claims the step's coupon; the claim advances the
reference NFT's `step`.

| | |
| --- | --- |
| **Inputs** | Reference NFT at the PLB [stake: holder], dereferenced to its `step: k-1` state. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | coupon policy: `1` unit of asset name `amount_k` (the step's amount in lovelace). |
| **Withdrawals** | The reference NFT's transfer chain (the claim is an owner-signed PLB spend). |
| **Signatures** | Holder. |
| **Outputs** | 1. **Coupon** at the holder's payment address: `cNt(amount_k)` × 1. 2. **Reference NFT** at the PLB [stake: holder], datum with `step: k`. |
| **Validity range** | Lower bound finite, `≥ d_k`. |
| **Constraints** | The coupon policy admits the mint only when the validity range reaches `d_k` **and** the spent reference NFT records `step: k-1`; the continuation must record `step: k`. This makes each step claimable exactly once (I3). |

### 4.4 Redemption (burn-to-pay, T-redeem)

A coupon is redeemed by burning it at the vault. The vault pays exactly the ADA
the burned coupons name.

| | |
| --- | --- |
| **Inputs** | Coupon UTxO(s) holding the `cNt`(s) to redeem; the **Vault** UTxO. |
| **Mint** | coupon policy: negative quantities (the coupons burned). |
| **Withdrawals** | None (the vault validator runs on the vault spend). |
| **Signatures** | The redeemer. |
| **Outputs** | 1. **Payout(s)**: ADA to the address(es) the redeemer names, summing to the redeemed amount. 2. **Vault continuation**: the vault UTxO with its ADA reduced by exactly the redeemed amount. |
| **Constraints** | The vault validator sums `decode(name) × burned_quantity` over the negative coupon mints and requires the vault's net ADA decrease to equal that sum exactly (I4). Nothing else leaves the vault on this path. |

### 4.5 Graduation (T4)

From `d4` on, the holder claims the principal-only coupon and retires the
reference NFT.

| | |
| --- | --- |
| **Inputs** | Reference NFT at the PLB [stake: holder], `step` at its final value. |
| **Mint** | coupon policy: `1` unit of asset name `principal` (the principal in lovelace). |
| **Withdrawals** | The reference NFT's transfer chain. |
| **Signatures** | Holder. |
| **Outputs** | 1. **Principal coupon** at the holder's payment address. 2. The reference NFT is **retired** (burned or spent without continuation). |
| **Validity range** | Lower bound finite, `≥ d4`. |
| **Constraints** | The principal amount comes from the reference NFT's datum, so the graduation cannot over- or under-claim. The principal coupon is then redeemed at the vault like any other coupon (§4.4). |

### 4.6 Owner extract (T-extract)

| | |
| --- | --- |
| **Inputs** | The **Vault** UTxO. |
| **Outputs** | 1. Payout to the owner. 2. Vault continuation with the remaining ADA. |
| **Signatures** | The vault owner. |
| **Constraints** | `OwnerExtract` is approved purely by the owner's signature: the owner may move any amount at any time. This is the instrument's explicit custody assumption (§7). |

## 5. Determinism & time

- §4.3 requires `now ≥ d_k`; the coupon amount is a schedule constant, so a
  late claim lands on the same amount — staleness costs nothing.
- §4.5 requires `now ≥ d4`; graduation never expires.
- §4.1, §4.2, §4.4 and §4.6 read no time bound.

## 6. Invariants

- **I1 — Certificate ownership.** Ownership of the reference NFT is its inline
  stake credential; it moves with the token, and transferring it transfers the
  right to future coupons and the principal claim.
- **I2 — Coupon value in the name.** A `cNt` is worth exactly the lovelace
  amount encoded in its asset name, and nothing else.
- **I3 — One claim per step.** A coupon for step `k` can be minted only when the
  spent reference NFT records `step: k-1` and the validity range reaches `d_k`;
  the continuation advances `step` to `k`. No step is claimable twice.
- **I4 — Burn-to-pay exactness.** On redemption the vault releases exactly
  `Σ decode(name) × burned_quantity` ADA — no more, no less — and the burned
  coupons are destroyed, so no coupon is paid twice.
- **I5 — Graduation integrity.** The graduation coupon names the reference
  NFT's recorded `principal`, and the reference NFT is retired.
- **I6 — Owner custody.** The vault owner may extract any ADA at any time; the
  instrument's solvency is an assumption, not an enforced invariant.

## 7. Threat model & assumptions

### Defended

- **Double claim.** The step anchor (I3) prevents minting a step's coupon more
  than once.
- **Double redemption.** Redemption burns the coupon (I4); a burned coupon
  cannot be spent again.
- **Over/under payment on redemption.** The vault validator recomputes the
  exact amount from the burned coupon names (I4), so a redeemer cannot request
  more than the coupons are worth, nor can the vault short-pay.
- **Wrong-amount coupons.** The coupon policy mints the schedule's `amount_k`
  at step `k` (I2); a coupon's name is its value.
- **Unauthorized coupon mint.** The claim requires the holder's reference NFT
  and signature, gated to the deadline (I3).
- **Payout redirection.** Redemptions pay only the addresses the redeemer names
  in the same transaction; the vault validator ties the payout total to the
  burned value.

### Assumptions / out of scope

- **Vault solvency and owner honesty.** The `OwnerExtract` path is
  unconditional: the company/country can drain the vault, in which case coupon
  and principal redemptions have nothing to pay. Holders trust the owner. This
  is the instrument's central custodial assumption (I6).
- **Pre-funding.** The vault is assumed funded with the principal plus the
  coupon amounts before redemptions occur.
- **Name collisions are intended.** Coupons are valued only by amount, so two
  steps of equal amount share an asset name and are fungible; the year is not
  encoded. If per-step distinctness is required, the name must encode more.
- **ADA-only.** The principal and payouts are lovelace.
- **Reference NFT custody.** The holder must hold the reference NFT to claim;
  losing it loses the remaining coupons and the principal claim (bounded by
  I1's transferability).
- **Regulatory framing.** The library ships code only; whether a tokenized bond
  is a security in a given jurisdiction is the deployer's concern.

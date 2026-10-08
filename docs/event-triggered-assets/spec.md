# Event-Triggered Assets — Tokenized Bond Specification

## 1. Summary

A **tokenized bond** backed by an ADA **vault**. The instrument is **registered
once** (the issuer creates its registry entry); afterwards **anyone may
deposit** a fixed bond unit: the principal moves into the vault and the same
transaction mints that depositor a CIP-113 **certificate** at the
Programmable Logic Base (PLB) — the holder-staked token carrying the unit's
claim state. Each certificate runs its **own timeline**, started at its deposit,
and claims **coupon tokens** (`cNt`) — one per scheduled step — each of which is
a plain native asset whose **asset name encodes the ADA amount** it is worth. A
`cNt` is redeemed by burning it at the vault: the vault validator pays out
exactly the ADA named by the burned coupons. At its maturity each certificate
claims a final `cNt` worth **only the principal** and retires its certificate.

Two postures make the instrument legible:

- **The certificate is the governed CIP-113 token.** One is minted per
  deposited unit and lives at the PLB, holder-staked (ownership = the UTxO's
  inline stake credential); it holds the claim state (`start`, `step`) and moves
  with the claim: whoever holds it may claim that unit's coupons still due. Its
  `step` anchor makes each coupon claimable exactly once per certificate.
- **Redemption is burn-to-pay.** A `cNt` is worth what its name says and only
  what its name says: the vault validator sums the amounts decoded from the
  burned coupon names and releases exactly that much ADA. The only residual
  trust is the vault's solvency and the owner's custody of it (§7).

> This specification **replaces** the earlier single-NFT 1:1 graduation model.
> The certificate still lives at the PLB — one per deposit, as described
> here — but the economics now flow through the vault and the coupon tokens,
> not through a burn-and-mint of the certificate.

### Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| Principal | **ADA held in a vault** | The bond is backed by lovelace in a dedicated UTxO; no fungible principal token is minted into the float. |
| Registration | **Register once, deposit many** | The issuer pins the instrument in the registry; every later unit deposit reuses it with no new registration. |
| Registry node | **Frozen stance** | `transfer` ours (step-monotone), `third_party` fail-closed, `unfracking` forbidden, empty global state; the minting logic refuses node updates. |
| Deposit | **Permissionless, principal-backed mint** | Anyone may deposit one unit; the minting logic admits the certificate only when the vault gains exactly the unit `principal` (I6). |
| Timeline | **Per certificate** | Each unit's deadlines are offsets from its deposit time (`start`, pinned at mint), so late deposits earn no past coupons. |
| Vault control | **Burn-to-pay redemptions** | Holders redeem by burning coupons; owner custody is an assumption, not enforced (§7). |
| Certificate | **One CIP-113 certificate per deposit at the PLB** | Each unit gets a holder-staked certificate carrying its own `start` / `step`. |
| Transfer | **Freely transferable, step-monotone** | Ownership moves with the token; the transfer logic preserves `start`, forbids `step` decreases, so a certificate cannot be rewound to re-claim. |
| Earnings | **`cNt` coupon tokens, amount in the name** | One native asset per step; the name is the amount, so the vault needs no external oracle or schedule. |
| Coupon claim | **Holder-signed, step-anchored** | The claim advances that certificate's `step`, so no step can be claimed twice per certificate. |
| Redemption | **Burn-to-pay at the vault** | Burning a coupon releases exactly `decode(name) × burned` ADA; double redemption is impossible (the coupon is destroyed). |
| Graduation | **Principal-only coupon at maturity** | A final `cNt` names the principal; the certificate is retired at its `start + o4` maturity. |
| Trust | **Explicit owner custody (assumed)** | The owner can withdraw the vault's ADA at any time; documented as the instrument's custody assumption (§7). |

## 2. Roles

- **User / holder / depositor**: anyone may deposit a bond unit — the principal
  ADA into the vault — and own the certificate minted for it. Claims coupons
  and redeems them; may transfer the certificate, which transfers the right to
  that unit's future coupons and principal claim.
- **Vault owner (company/country)**: controls the vault, created and funded
  outside this design, and may withdraw its ADA at any time; this custody is
  assumed, not enforced on-chain (§7).
- **Issuer**: registers the instrument (the RegistryNode) once; mints no
  certificate and does not control coupons or the vault.
- **Vault**: an ADA UTxO with a small validator enforcing the redemption path
  (§4.5).
- **Coupon policy**: the minting policy of the `cNt` native assets (§4.4).
- **Core protocol** (trusted infrastructure): the CIP-113 PLB and the
  transfer / issuance validators that custody and move the certificate.

## 3. State model

### 3.1 Vault

An ADA UTxO that holds the deposited principals plus the owner's own funds. It
is **created and funded by the owner outside this design**, and each deposit
adds one unit's principal, so coupon and principal redemptions are
deterministically payable while the vault is solvent. Its inline datum binds
the instrument's coupon policy:

| Field | Meaning |
| --- | --- |
| `cnt_policy` | The coupon policy whose negative mints the `Redeem` path honors. |

The vault owner lives off-chain — custody is the instrument's central
assumption (§7), not a datum field. The vault is governed by a validator with
a single redemption path:

| Redeemer | Admitted when | Effect |
| --- | --- | --- |
| `Redeem` | no owner signature needed | The vault's net ADA loss equals the sum decoded from the burned coupons; the payout(s) go to the address(es) the redeemer names. |

The vault is a single UTxO (or a small set); a redemption spends it and
re-outputs the remainder. Solvency is an assumption, not an invariant (§7).

### 3.2 Coupon token (`cNt`)

A plain native asset under the **coupon policy**, with no CIP-113 custody. One
coupon is minted per scheduled step and per certificate:

| Field | Meaning |
| --- | --- |
| policy id | The coupon policy's id. |
| asset name | The coupon's value **in lovelace, decimal**: name `"1124"` is worth `1124` lovelace. |
| quantity | `1` per claim (a coupon is a single claim unit). |

Because the name is only the amount, two coupons of equal amount are the same
asset (they are fungible with each other). This is intended: redeeming any unit
of `"1124"` pays `1124` lovelace, regardless of which step it came from.

### 3.3 Certificate (the CIP-113 token, one per deposit)

The instrument's certificate and state anchor. One is minted per deposited bond
unit: quantity `1`, custodied at the PLB with the depositor as its inline stake
credential. Its inline datum carries only the per-certificate claim state:

| Field | Meaning |
| --- | --- |
| `start` | The unit's timeline origin, pinned at deposit to the transaction's validity **upper** bound (required finite). Preserved byte-for-byte by every transfer. |
| `step` | The number of the last coupon claimed (`0` at deposit); monotone (never decreases), and the claim anchor that makes each step claimable once per certificate. |

The schedule offsets and amounts and the unit principal are deployment
constants baked into the coupon policy / minting logic, so every certificate
shares them and they are not certificate state.

Ownership of a certificate is the claim on its unit: transferring it transfers
that unit's remaining coupons and principal claim.

### 3.4 Schedule

A non-empty, ascending sequence of `(offset, amount)` steps, precomputed
off-chain and baked as deployment constants. A certificate may claim the coupon
`amount_k` once `now ≥ start + offset_k`; the final offset `o4` opens its
graduation (principal) claim. Each unit therefore matures at `start + o4`, and
only the per-certificate `start` / `step` live in the datum.

## 4. Transactions

Each section is one complete transaction. Withdrawals are listed by role; the
ledger presents them in its canonical order and builders derive indices from
the sorted set.

### 4.1 Register (T0)

The issuer inserts the instrument's RegistryNode into the CIP-113 registry. No
certificate is minted here, so the same registration serves every deposit.

| | |
| --- | --- |
| **Inputs** | Issuer wallet funds: `min_ada` + fees; the **covering RegistryNode** (spent by the insertion). |
| **Reference inputs** | The one-shot **`IssuanceCborHex` template** (locked at the always-fail address), which binds `cip_policy` to the minting logic. |
| **Mint** | `registry mint handler`: `1` (the node NFT named `cip_policy`). |
| **Withdrawals** | Minting logic `[Register]` (0) — registration authority, register-only check and node stance. No `issuance_logic` withdraw-0: no token is minted, so `issuance_mint` never runs. |
| **Outputs** | 1. **Covering node** re-emitted with `next = cip_policy`. 2. **New node**: `key = cip_policy`, datum pinning `minting_logic` (ours, `Register` / deny updates), `transfer_logic` (ours, step-monotone), `third_party_logic` (fail-closed), `unfracking_logic` `empty_vkey` (forbidden) and an empty `global_state_cs`. 3. Change. |
| **Signatures** | Issuer. |
| **Constraints** | The `Register` mode authorises the issuer, asserts `tx.mint` carries no `cip_policy` entries (register-only) and refuses in-place node updates, so the recorded stance is frozen for the instrument's life. Exactly one node is created for the governed `cip_policy`; the vault is assumed created and funded by the owner outside this design (§7). |

### 4.2 Deposit (unit, T-deposit)

Anyone deposits one bond unit: the principal ADA moves into the vault and the
same transaction mints that depositor's certificate.

| | |
| --- | --- |
| **Inputs** | Depositor wallet funds: the unit `principal` + `min_ada` + fees; the **Vault** UTxO. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `1` (the depositor's certificate) — the core `issuance_mint` policy with the minting logic's `Deposit` mode. |
| **Withdrawals** | The certificate's issuance chain (minting logic `[Deposit]` + core `issuance_mint`). |
| **Signatures** | Depositor (only to spend their own wallet funds; the mint itself is permissionless). |
| **Outputs** | 1. **Vault**: input ADA **+ the unit `principal`**, datum preserved. 2. **Certificate** at the PLB [stake: depositor]: `cip_policy` × 1, datum `{ start: upper, step: 0 }`. 3. Change. |
| **Constraints** | Deposit integrity (I6): the mint is admitted only when the vault's net ADA gain equals exactly the baked unit `principal`, so the certificate and its backing exist atomically. The `Deposit` mode pins `start` to the transaction's validity **upper** bound (required finite); since the ledger guarantees `now ≤ upper`, the timeline origin can never precede the real deposit — a builder can only set it later, at the depositor's own cost. It also requires exactly `1` unit of the certificate asset to the new UTxO and no certificate inputs, so units can never be merged (I8); its datum records `step: 0`. |

### 4.3 Transfer the certificate (T1)

The certificate is a CIP-113 token at the PLB; moving it moves the claim.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: sender], `cip_policy` × 1. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] → `transfer` → `transfer_logic` (ours). |
| **Signatures** | Sender. |
| **Outputs** | Certificate at the PLB [stake: recipient], `cip_policy` × 1, datum preserved. |
| **Constraints** | At most one certificate per transaction and exactly `1` unit in and out — no merge or split (I8). The transfer logic resolves the governed `cip_policy` from the RegistryNode and decodes the input and continuation datums: a continuation must record the same `step` (plain transfer) or exactly `step + 1` (the coupon claim, §4.4), never less (I7). A transaction with no continuation is admitted only alongside the matching `cip_policy` burn — the retirement shape (§4.6). |

### 4.4 Coupon claim (step k, T-k)

At `now ≥ start + offset_k` each certificate may claim the step's coupon; the
claim advances that certificate's `step`.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: holder], dereferenced to its `{ start, step: k-1 }` state. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | coupon policy: `1` unit of asset name `amount_k` (the step's amount in lovelace). |
| **Withdrawals** | The certificate's transfer chain (the claim is an owner-signed PLB spend). |
| **Signatures** | Holder. |
| **Outputs** | 1. **Coupon** at the holder's payment address: `cNt(amount_k)` × 1. 2. **Certificate** at the PLB [stake: holder], datum `{ start, step: k }`. |
| **Validity range** | Lower bound finite, `≥ start + offset_k`. |
| **Constraints** | The coupon policy admits the mint only when the validity range reaches that certificate's baked `start + offset_k` and the spent certificate records `step: k-1`; the continuation must record the same `start` and `step: k` — the only advance the transfer logic admits (I7). Advancing without the mint simply forfeits that coupon. This makes each step claimable exactly once per certificate (I3). |

### 4.5 Redemption (burn-to-pay, T-redeem)

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

### 4.6 Graduation (T4)

From `start + o4` on, the certificate's holder may claim the principal-only
coupon and burn the certificate (retirement).

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: holder], `{ start, step: final }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−1` (the certificate burned, under the `issuance_mint` policy) — our minting logic's `Retire` mode. Coupon policy: `1` unit of asset name `principal` (the principal in lovelace). |
| **Withdrawals** | The certificate's transfer chain; minting logic `[Retire]` → core `issuance_mint`. |
| **Signatures** | Holder. |
| **Outputs** | **Principal coupon** at the holder's payment address; no certificate continuation. |
| **Validity range** | Lower bound finite, `≥ start + o4`. |
| **Constraints** | Our minting logic's `Retire` validates the burn shape (exactly `−1` of the certificate asset), the certificate's `start + o4` maturity, the final `step` and the principal payout; the transfer logic admits a no-continuation spend only on this burn shape (I7). The principal amount is the baked unit, so the graduation cannot over- or under-claim. The principal coupon is then redeemed at the vault like any other coupon (§4.5). |

## 5. Determinism & time

- §4.2 pins `start` to the deposit transaction's validity upper bound (finite);
  the ledger guarantees `now ≤ upper`, so the timeline origin can never precede
  the real deposit — it can only be set later, at the depositor's own cost.
- §4.4 requires `now ≥ start + offset_k`; the coupon amount is a schedule
  constant, so a late claim lands on the same amount — staleness costs nothing.
- §4.6 requires `now ≥ start + o4`; each unit's graduation never expires.
- §4.1, §4.3 and §4.5 read no time bound.

## 6. Invariants

- **I1 — Certificate ownership.** Ownership of a certificate is its inline
  stake credential; it moves with the token, and transferring it transfers that
  unit's right to future coupons and the principal claim.
- **I2 — Coupon value in the name.** A `cNt` is worth exactly the lovelace
  amount encoded in its asset name, and nothing else.
- **I3 — One claim per step, per certificate.** A coupon for step `k` can be
  minted only when the spent certificate records `step: k-1` and the validity
  range reaches that certificate's `start + offset_k`; the continuation
  advances `step` to `k` and preserves `start`. The coupon policy binds every
  advance to its mint and the transfer logic forbids step decreases (I7), so no
  certificate can claim a step twice.
- **I4 — Burn-to-pay exactness.** On redemption the vault releases exactly
  `Σ decode(name) × burned_quantity` ADA — no more, no less — and the burned
  coupons are destroyed, so no coupon is paid twice.
- **I5 — Graduation integrity.** The graduation coupon names the baked unit
  `principal`, and the certificate is retired at its `start + o4` maturity.
- **I6 — Deposit integrity.** A certificate can be minted only in a
  transaction that increases the vault's ADA by exactly the baked unit
  `principal`, and its `start` is pinned to the transaction's validity upper
  bound (finite), so no unbacked certificate exists and its timeline cannot be
  backdated.
- **I7 — Step monotonicity.** On any spend of a certificate with a
  continuation, the continuation preserves `start` byte-for-byte and records
  the same `step` or exactly `step + 1` — never less — and a certificate is
  retired only by a `cip_policy` burn at its final step, on or after its
  `start + o4` maturity.
- **I8 — Certificate unit integrity.** Every certificate UTxO carries exactly
  `1` unit of the certificate asset under `cip_policy`; deposits mint exactly
  one and transfers neither merge nor split certificates.

## 7. Threat model & assumptions

### Defended

- **Double claim.** The step anchor (I3) prevents minting a step's coupon more
  than once per certificate, and step monotonicity (I7) prevents rewinding a
  certificate to re-claim.
- **Step rewind.** The transfer logic rejects any continuation whose `step` is
  lower than the spent certificate's, so a claimed step cannot be reset and
  re-claimed (I7).
- **Backdated start.** The `Deposit` mode pins `start` to the validity upper
  bound (finite), and `upper ≥ now` by construction, so a depositor cannot
  backdate its timeline to claim coupons from before it deposited (I6).
- **Certificate merge/split.** The module's deposit and transfer logic hold
  every certificate UTxO to exactly one unit (I8), so `step` accounting cannot
  be diluted across merged certificates.
- **Double redemption.** Redemption burns the coupon (I4); a burned coupon
  cannot be spent again.
- **Over/under payment on redemption.** The vault validator recomputes the
  exact amount from the burned coupon names (I4), so a redeemer cannot request
  more than the coupons are worth, nor can the vault short-pay.
- **Wrong-amount coupons.** The coupon policy mints the schedule's `amount_k`
  at step `k` (I2); a coupon's name is its value.
- **Unauthorized coupon mint.** The claim requires the holder's certificate
  and signature, gated to that certificate's `start + offset_k` (I3).
- **Unbacked certificates.** The `Deposit` mint mode requires the vault's net
  ADA gain to equal the baked unit `principal` (I6), so a certificate cannot be
  minted without its backing.
- **Forged certificate terms.** The certificate datum holds only `start` and
  `step`; the schedule offsets and amounts and the unit principal are baked
  validator constants, so rewriting the datum cannot forge the coupon amounts
  or the principal — and a transfer cannot move `start` (I7).
- **Payout redirection.** Redemptions pay only the addresses the redeemer names
  in the same transaction; the vault validator ties the payout total to the
  burned value.

### Assumptions / out of scope

- **Vault solvency and owner honesty.** The owner has unconditional custody of
  the vault: the company/country can drain it at any time, in which case coupon
  and principal redemptions have nothing to pay. Holders trust the owner. This
  is the instrument's central custodial assumption; the owner-extract path and
  the vault's detailed validator logic are out of scope.
- **Vault creation and pre-funding.** The vault is assumed created and funded
  by the owner outside this design. Each deposit adds its unit's principal; the
  owner is assumed to fund each unit's coupon amounts before its redemptions
  occur — depositing does not itself fund coupons. Because units start on their
  own timer, the owner's coupon liability extends with every deposit.
- **Open issuance, no cap.** Deposits are permissionless and the number of
  certificates is not capped on-chain: every certificate claims the schedule's
  coupons from the owner-funded vault and the principal at its own
  `start + o4` maturity. The owner must manage total issuance off-chain;
  holders trust it to fund and honor all certificates.
- **Name collisions are intended.** Coupons are valued only by amount, so two
  steps of equal amount share an asset name and are fungible; the year is not
  encoded. If per-step distinctness is required, the name must encode more.
- **ADA-only.** The principal and payouts are lovelace.
- **Certificate custody.** The holder must hold a certificate to claim from its
  unit; losing it loses that unit's remaining coupons and the principal claim
  (bounded by I1's transferability).
- **Regulatory framing.** The library ships code only; whether a tokenized bond
  is a security in a given jurisdiction is the deployer's concern.

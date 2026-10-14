# Event-Triggered Assets — Tokenized Bond Specification

## 1. Summary

A **tokenized bond** backed by an ADA **vault**. The instrument is **registered
once** (the issuer creates its registry entry); afterwards **anyone may
deposit** a fixed bond unit: the principal moves into the vault and the same
transaction mints that depositor a CIP-113 **certificate** at the
Programmable Logic Base (PLB) — the holder-staked token whose **asset name
encodes the current step** and whose datum carries the rest of its claim state.
Each certificate runs its **own timeline**, started at its deposit, and claims
**coupon tokens** (`cNt`) — one per scheduled step — each of which is a plain
native asset whose **asset name encodes the ADA amount** it is worth. A `cNt`
is redeemed by burning it at the vault: the vault validator pays out exactly
the ADA named by the burned coupons. At its maturity each certificate claims a
final `cNt` worth **only the principal** and is retired.

Three postures make the instrument legible:

- **The certificate is the governed CIP-113 token.** One is minted per
  deposited unit and lives at the PLB, holder-staked (ownership = the UTxO's
  inline stake credential); its **asset name's first byte is the current step**
  and its datum holds `{start, commit}`. Every claim **burns the current name
  and mints the next**, so the state advances in place: whoever holds it may
  claim that unit's coupons still due, exactly once per step.
- **Redemption is burn-to-pay.** A `cNt` is worth what its name says and only
  what its name says: the vault validator sums the amounts decoded from the
  burned coupon names and releases exactly that much ADA. The only residual
  trust is the vault's solvency and the owner's custody of it (§7).
- **Issuer triggering is opt-in.** An owner may commit a payment credential to
  the certificate with a signed self-transfer (§4.4); the issuer can then
  trigger each coupon claim and the final graduation through the CIP-113
  third-party path — holder-passive, always paying the committed credential.
  Because the step rides the asset name, an issuer-claimed coupon leaves no
  ghost shell: the paired continuation is the next certificate. The owner can
  revoke at any time and always retains the self-service path.

> This specification **replaces** the earlier single-NFT 1:1 graduation model.
> The certificate still lives at the PLB — one per deposit, as described
> here — but the economics now flow through the vault and the coupon tokens,
> not through a burn-and-mint of the certificate.

### Design choices

| Decision | Choice | Rationale |
| --- | --- | --- |
| Principal | **ADA held in a vault** | The bond is backed by lovelace in a dedicated UTxO; no fungible principal token is minted into the float. |
| Registration | **Register once, deposit many** | The issuer pins the instrument in the registry; every later unit deposit reuses it with no new registration. |
| Registry node | **Frozen stance** | `transfer` ours (name-monotone), `third_party` ours (issuer-triggered, opt-in), `unfracking` forbidden, empty global state; the minting logic refuses node updates. |
| Deposit | **Permissionless, principal-backed mint** | Anyone may deposit one unit; the minting logic admits the certificate only when the vault gains exactly the unit `principal` (I6). |
| Timeline | **Per certificate** | Each unit's deadlines are multiples of a baked `interval` after its deposit time (`start`, pinned at mint), so late deposits earn no past coupons. |
| Vault control | **Burn-to-pay redemptions** | Holders redeem by burning coupons; owner custody is an assumption, not enforced (§7). |
| Certificate | **One CIP-113 certificate per deposit at the PLB** | Each unit gets a holder-staked certificate whose name carries the step and whose datum carries `start` / `commit`. |
| Authorize | **Owner opt-in via self-transfer** | A signed self-transfer (same stake) commits a payment credential to the certificate; it is cleared automatically when the owner changes. |
| Trigger | **Issuer-triggered, holder-passive, destination-bound** | When a certificate is committed, the issuer may trigger its coupon claims and graduation through the third-party path; every payout goes to the committed credential. |
| Transfer | **Freely transferable, name-monotone** | Ownership moves with the token; the transfer logic preserves the name and `start`, so a certificate cannot be rewound to re-claim. |
| Earnings | **`cNt` coupon tokens, amount in the name** | One native asset per step; the name is the amount, so the vault needs no external oracle or schedule. |
| Coupon claim | **Name-anchored; owner-signed or issuer-triggered** | The claim burns the current name and mints the next, so no step can be claimed twice per certificate; a committed certificate may be claimed by the issuer. |
| Redemption | **Burn-to-pay at the vault** | Burning a coupon releases exactly `decode(name) × burned` ADA; double redemption is impossible (the coupon is destroyed). |
| Graduation | **Principal-only coupon at maturity** | A final `cNt` names the principal; the certificate is retired at its `start + N * interval` maturity (owner-signed or issuer-triggered). |
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
  certificate and does not control coupons or the vault. When a certificate
  commits a payment credential (§4.4), the issuer may trigger its coupon claims
  and graduation through the third-party path, always paying the commitment.
- **Vault**: an ADA UTxO with a small validator enforcing the redemption path
  (§4.6).
- **Coupon policy**: the minting policy of the `cNt` native assets (§4.5).
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
credential. Its state is split between the asset name and the inline datum:

| Field | Meaning |
| --- | --- |
| name | The **current step in the first byte** (`0` at deposit, `N` at maturity; the rest of the name is reserved). The name advances only by burning the current one and minting the next (I7). |
| `start` | The unit's timeline origin, pinned at deposit to the transaction's validity **upper** bound (required finite). Preserved byte-for-byte by every transition. |
| `commit` | `Option<Credential>` — the owner's committed payment credential for issuer-triggered claims (`None` at deposit). Settable/clearable only by an owner-signed self-transfer, and cleared whenever the owner (stake credential) changes. |

Because the step travels in the asset name — and the third-party path pins the
paired output's `datum` but **not the subject policy's asset names** — an
issuer-triggered claim can replace the certificate in place (`name k-1 → name
k`) and leaves no certificate-less shell behind.

The interval, the per-step amounts and the unit principal are deployment
constants baked into the coupon policy / minting logic, so every certificate
shares them and they are not certificate state.

Ownership of a certificate is the claim on its unit: transferring it transfers
that unit's remaining coupons and principal claim.

### 3.4 Schedule

A fixed number `N` of coupon steps on a **constant interval**: step `k` opens
at `start + k * interval` (`interval` baked; step `N` opens graduation). The
amounts `amount_1 … amount_N` and the unit principal are baked deployment
constants. A certificate may claim the coupon `amount_k` once the validity
range reaches `start + k * interval`; each unit matures at
`start + N * interval`. The first byte of the certificate's asset name carries
the current step, so no `step` lives in the datum.

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
| **Outputs** | 1. **Covering node** re-emitted with `next = cip_policy`. 2. **New node**: `key = cip_policy`, datum pinning `minting_logic` (ours, `Register` / deny updates), `transfer_logic` (ours, name-monotone), `third_party_logic` (ours, issuer-triggered opt-in), `unfracking_logic` `empty_vkey` (forbidden) and an empty `global_state_cs`. 3. Change. |
| **Signatures** | Issuer. |
| **Constraints** | The `Register` mode authorises the issuer, asserts `tx.mint` carries no `cip_policy` entries (register-only) and refuses in-place node updates, so the recorded stance is frozen for the instrument's life. Exactly one node is created for the governed `cip_policy`; the vault is assumed created and funded by the owner outside this design (§7). |

### 4.2 Deposit (unit, T-deposit)

Anyone deposits one bond unit: the principal ADA moves into the vault and the
same transaction mints that depositor's certificate.

| | |
| --- | --- |
| **Inputs** | Depositor wallet funds: the unit `principal` + `min_ada` + fees; the **Vault** UTxO. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `1` of name step `0` (the depositor's certificate) — the core `issuance_mint` policy with the minting logic's `Deposit` mode. |
| **Withdrawals** | The certificate's issuance chain (minting logic `[Deposit]` + core `issuance_mint`). |
| **Signatures** | Depositor (only to spend their own wallet funds; the mint itself is permissionless). |
| **Outputs** | 1. **Vault**: input ADA **+ the unit `principal`**, datum preserved. 2. **Certificate** at the PLB [stake: depositor]: `cip_policy` × 1 of name step `0`, datum `{ start: upper, commit: None }`. 3. Change. |
| **Constraints** | Deposit integrity (I6): the mint is admitted only when the vault's net ADA gain equals exactly the baked unit `principal`, so the certificate and its backing exist atomically. The `Deposit` mode pins `start` to the transaction's validity **upper** bound (required finite) and mints exactly the step-`0` name, quantity `1`; since the ledger guarantees `now ≤ upper`, the timeline origin can never precede the real deposit — a builder can only set it later, at the depositor's own cost. It also rejects certificate inputs, so units can never be merged (I8); the datum records `commit: None`. |

### 4.3 Transfer the certificate (T1)

The certificate is a CIP-113 token at the PLB; moving it moves the claim.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: sender], name step `k`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] → `transfer` → `transfer_logic` (ours). |
| **Signatures** | Sender. |
| **Outputs** | Certificate at the PLB [stake: recipient], same name step `k`, datum preserved. |
| **Constraints** | At most one certificate per transaction and exactly `1` unit in and out — no merge or split (I8). The transfer logic resolves the governed `cip_policy` from the RegistryNode and compares input and continuation: the continuation preserves the name step and `start`, and may change `commit` only when the stake credential does not change (the owner's self-transfer, §4.4) — on an owner change `commit` must be `None`. Only the coupon claim (§4.5) burns the current name and mints the next (I7). A transaction with no continuation is admitted only alongside the matching `cip_policy` burn — the retirement shape (§4.7). |

### 4.4 Authorize claims (self-transfer, T-opt-in)

The owner opts in to issuer triggering — or revokes it — with a signed
self-transfer that writes (or clears) the certificate's `commit`.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: owner], name step `k`, `{ start, commit }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Withdrawals** | `programmable_logic_global` [TransferAct] → `transfer` → `transfer_logic` (ours). |
| **Signatures** | Owner. |
| **Outputs** | Certificate at the PLB [stake: owner], same name step `k`, `{ start, commit: Some(pay) }` — or `None` to revoke. |
| **Constraints** | `commit` may change only when the input and output stake credentials are equal (a self-transfer, §4.3); the name step and `start` are preserved (I7). Only the owner can authorise it, so the commitment is authentic; it is cleared automatically whenever the owner changes, so the issuer can never pay a previous owner. |

### 4.5 Coupon claim (step k, T-k)

At `now ≥ start + k * interval` the step's coupon may be claimed: the owner
claims it directly (transfer path), or — when the owner has committed a
payment credential (§4.4) — the issuer triggers it on the owner's behalf
(third-party path). Either way the claim **burns the certificate's name `k-1`
and mints the name `k` one**, plus the coupon.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: holder], name step `k-1`, `{ start, commit }`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−1` of name `k-1` + `+1` of name `k` (our minting logic's `Advance` mode); coupon policy: `1` unit of asset name `amount_k`. |
| **Withdrawals** | The certificate's transfer chain; minting logic `[Advance]` → core `issuance_mint`. |
| **Signatures** | Holder. |
| **Outputs** | 1. **Coupon** at the holder's payment address: `cNt(amount_k)` × 1. 2. **Certificate** at the PLB [stake: holder], name step `k`, datum `{ start, commit }` preserved. |
| **Validity range** | Lower bound finite, `≥ start + k * interval`. |
| **Constraints** | The coupon policy admits the mint only when the validity range reaches that certificate's baked `start + k * interval`, the spent name is step `k-1` and the continuation's name is step `k` with `start`/`commit` preserved. The minting logic's `Advance` mode validates the burn/mint shape. This makes each step claimable exactly once per certificate (I3). |

**Issuer-triggered shape (`commit: Some(pay)`).** The issuer claims on the
owner's behalf through the third-party path:

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: owner], name step `k-1`, `commit: Some(pay)`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−1` of name `k-1` + `+1` of name `k` (our minting logic's `Advance` mode); coupon policy: `1` unit of asset name `amount_k`. |
| **Withdrawals** | `programmable_logic_global` [ThirdPartyAct] → `third_party` [ThirdPartyRedeemer] → `third_party_logic` (ours); minting logic `[Advance]` → core `issuance_mint`. |
| **Signatures** | Issuer. |
| **Outputs** | 1. **Certificate**: the paired PLB output at the same address and `datum`, name step `k` — the next certificate itself, so **no ghost shell**. 2. **Coupon** at `[payment: pay]`: `cNt(amount_k)` × 1. |
| **Validity range** | Lower bound finite, `≥ start + k * interval`. |
| **Constraints** | The third-party path pins the paired output's address and `datum` but **not the subject policy's asset name**, so the pair can carry the name `k` certificate in place. `third_party_logic` requires the issuer's signature, `commit = Some(pay)`, the exact `k-1 → k` transition and binds the coupon to `pay`; the base layer enforces one policy per transaction and the aggregate conservation rail (the burn and mint balance). |

### 4.6 Redemption (burn-to-pay, T-redeem)

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

### 4.7 Graduation (T4)

From `start + N * interval` on, the certificate's holder may claim the
principal-only coupon and retire the certificate; or — when committed — the
issuer triggers the retirement on the owner's behalf through the third-party
path.

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: holder], name step `N`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−1` of name `N` (the certificate burned, under the `issuance_mint` policy) — our minting logic's `Retire` mode. Coupon policy: `1` unit of asset name `principal` (the principal in lovelace). |
| **Withdrawals** | The certificate's transfer chain; minting logic `[Retire]` → core `issuance_mint`. |
| **Signatures** | Holder. |
| **Outputs** | **Principal coupon** at the holder's payment address; no certificate continuation. |
| **Validity range** | Lower bound finite, `≥ start + N * interval`. |
| **Constraints** | Our minting logic's `Retire` validates the burn shape (exactly `−1` of name `N`), the certificate's `start + N * interval` maturity and the principal payout; the transfer logic admits a no-continuation spend only on this burn shape (I7). The principal amount is the baked unit, so the graduation cannot over- or under-claim. The principal coupon is then redeemed at the vault like any other coupon (§4.6). |

**Issuer-triggered shape (`commit: Some(pay)`).** The issuer retires on the
owner's behalf:

| | |
| --- | --- |
| **Inputs** | Certificate at the PLB [stake: owner], name step `N`, `commit: Some(pay)`. |
| **Reference inputs** | Protocol params; RegistryNode. |
| **Mint** | `cip_policy`: `−1` of name `N` — our minting logic's `Retire` mode; coupon policy: `1` unit of asset name `principal`. |
| **Withdrawals** | `programmable_logic_global` [ThirdPartyAct] → `third_party` [ThirdPartyRedeemer] → `third_party_logic` (ours); minting logic `[Retire]` → core `issuance_mint`. |
| **Signatures** | Issuer. |
| **Outputs** | 1. **Ghost continuation**: paired PLB output at the same address and `datum` with the certificate removed (`min_ada`) — the design's only shell. 2. **Principal coupon** at `[payment: pay]`: `cNt(principal)` × 1. |
| **Validity range** | Lower bound finite, `≥ start + N * interval`. |
| **Constraints** | The burn's custody is covered by the third-party path (the core `issuance_logic` delegates to it); `third_party_logic` requires the issuer's signature and `commit`, validates name `N`, and binds the principal coupon to `pay`. Because the certificate disappears, the pair output is a certificate-less shell — inert and sweepable (§7). |

## 5. Determinism & time

- §4.2 pins `start` to the deposit transaction's validity upper bound (finite);
  the ledger guarantees `now ≤ upper`, so the timeline origin can never precede
  the real deposit — it can only be set later, at the depositor's own cost.
- §4.5 requires `now ≥ start + k * interval`; the coupon amount is a schedule
  constant, so a late claim lands on the same amount — staleness costs nothing.
- §4.7 requires `now ≥ start + N * interval`; each unit's graduation never
  expires.
- §4.1, §4.3, §4.4 and §4.6 read no time bound.

## 6. Invariants

- **I1 — Certificate ownership.** Ownership of a certificate is its inline
  stake credential; it moves with the token, and transferring it transfers that
  unit's right to future coupons and the principal claim.
- **I2 — Coupon value in the name.** A `cNt` is worth exactly the lovelace
  amount encoded in its asset name, and nothing else.
- **I3 — One claim per step, per certificate.** A coupon for step `k` can be
  minted only when the spent certificate's name is step `k-1`, the continuation
  (or the third-party paired output) carries step `k`, and the validity range
  reaches `start + k * interval`. The coupon policy binds the advance to its
  mint and the minting logic's `Advance` burns the old name and mints the new
  one, so no certificate can claim a step twice.
- **I4 — Burn-to-pay exactness.** On redemption the vault releases exactly
  `Σ decode(name) × burned_quantity` ADA — no more, no less — and the burned
  coupons are destroyed, so no coupon is paid twice.
- **I5 — Graduation integrity.** The graduation coupon names the baked unit
  `principal`, and the certificate is retired at its `start + N * interval`
  maturity.
- **I6 — Deposit integrity.** A certificate can be minted only in a
  transaction that increases the vault's ADA by exactly the baked unit
  `principal`, and its `start` is pinned to the transaction's validity upper
  bound (finite), so no unbacked certificate exists and its timeline cannot be
  backdated.
- **I7 — Certificate name monotonicity.** The certificate's asset name carries
  the step; it can only stay (plain transfer / opting) or advance by exactly
  one (the claim's burn+mint) — never decrease. `start` is preserved
  byte-for-byte, `commit` may change only on a self-transfer (same stake) and
  must be `None` on an owner change; and a certificate is retired only by a
  `cip_policy` burn of name `N`, on or after its `start + N * interval`
  maturity.
- **I8 — Certificate unit integrity.** Every certificate UTxO carries exactly
  `1` unit of exactly one certificate name under `cip_policy`; deposits mint
  exactly the step-`0` name and transfers neither merge nor split certificates.
- **I9 — Committed issuer trigger.** An issuer-triggered claim or graduation
  spends the certificate through the third-party path only when its datum
  commits a payment credential (`Some(pay)`), and the coupon and principal
  payouts go to `pay` — the issuer can trigger but never redirect. An
  issuer-claimed coupon's paired output is the next certificate (no shell);
  `commit` is owner-set and cleared on owner change (I7).

## 7. Threat model & assumptions

### Defended

- **Double claim.** The name anchor (I3) prevents minting a step's coupon more
  than once per certificate, and name monotonicity (I7) prevents rewinding a
  certificate to re-claim.
- **Name rewind.** The minting logic's `Advance` burns the current name and
  mints only the next, so a certificate cannot be moved to an earlier name or
  skip a step (I7).
- **Trigger payout redirection.** Every issuer-triggered payout is bound to the
  certificate's committed payment credential (I9); the issuer can trigger the
  event but cannot redirect the coupon or the principal.
- **Stale consent.** `commit` is cleared automatically whenever the owner
  changes (I7), so an issuer can never pay a previous owner.
- **Early trigger.** The coupon and graduation gates are the same on both
  paths, so the issuer cannot claim before `start + k * interval` (I3) nor
  retire before `start + N * interval` (I5).
- **Backdated start.** The `Deposit` mode pins `start` to the validity upper
  bound (finite), and `upper ≥ now` by construction, so a depositor cannot
  backdate its timeline to claim coupons from before it deposited (I6).
- **Certificate merge/split.** The module's deposit and transfer logic hold
  every certificate UTxO to exactly one unit with one name (I8), so `step`
  accounting cannot be diluted across merged certificates.
- **Double redemption.** Redemption burns the coupon (I4); a burned coupon
  cannot be spent again.
- **Over/under payment on redemption.** The vault validator recomputes the
  exact amount from the burned coupon names (I4), so a redeemer cannot request
  more than the coupons are worth, nor can the vault short-pay.
- **Wrong-amount coupons.** The coupon policy mints the schedule's `amount_k`
  at step `k` (I2); a coupon's name is its value.
- **Unauthorized coupon mint.** The claim requires the spent certificate and
  either the owner's signature (transfer path) or a committed payment
  credential plus the issuer's signature (third-party path), gated to
  `start + k * interval` (I3, I9).
- **Unbacked certificates.** The `Deposit` mint mode requires the vault's net
  ADA gain to equal the baked unit `principal` (I6), so a certificate cannot be
  minted without its backing.
- **Forged certificate terms.** The certificate datum holds only `start` and
  `commit`, and the step lives in the asset name; the interval, amounts and the
  unit principal are baked validator constants, so rewriting the datum cannot
  forge the coupon amounts or the principal — and a transfer cannot move
  `start`, change the step name, nor set `commit` on someone else's behalf
  (I7).
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
  `start + N * interval` maturity. The owner must manage total issuance
  off-chain; holders trust it to fund and honor all certificates.
- **Name collisions are intended.** Coupons are valued only by amount, so two
  steps of equal amount share an asset name and are fungible; the year is not
  encoded. If per-step distinctness is required, the name must encode more.
- **ADA-only.** The principal and payouts are lovelace.
- **Certificate custody.** The holder must hold a certificate to claim from its
  unit; losing it loses that unit's remaining coupons and the principal claim
  (bounded by I1's transferability).
- **Issuer liveness.** Issuer triggering is a convenience: if the issuer never
  triggers, the owner can always claim and graduate through the transfer path.
- **Issuer graduation leaves one shell.** An issuer-claimed coupon pairs to the
  next certificate, so claims leave no shell; only the issuer's *graduation*
  removes the certificate, leaving a certificate-less paired continuation (a
  *ghost shell*) holding ratcheted `min_ada`. It is inert — no `cip_policy`, no
  effect on claims or graduation, and third-party cannot touch it (the paired
  input must already hold the policy). The owner can sweep any number of shells
  in a single owner-signed transfer-path spend (`PLG [TransferAct]` +
  `transfer`; that path does not require paired outputs) and recover the
  `min_ada`; the issuer cannot (the stake is the owner's), and a CIP-113-aware
  builder is required.
- **The certificate's asset id changes every step.** The step rides the first
  byte of the asset name, so a unit is a different asset at each step (`0…N`).
  Wallets and indexers must follow the name transition; the certificate is
  always the one unit of the latest name.
- **Regulatory framing.** The library ships code only; whether a tokenized bond
  is a security in a given jurisdiction is the deployer's concern.

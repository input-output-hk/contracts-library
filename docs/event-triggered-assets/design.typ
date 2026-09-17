#import "../diagrams-template.typ": *

#show: report

= Tokenized bond — register + issue (T0/T1)
_One transaction registers the CIP-113 instance and mints the first tokens to
the beneficiary, publishing the bond's terms as a CIP-68 reference datum._

#let bond_register_issue_tx = vanilla_transaction(
  "Register + issue",
  inputs: (
    (
      name: "Issuer funds",
      wallet: true,
      address: "issuer_addr",
      value: ("ADA": "min_ada", "FeeAsset": "f"),
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
  ),
  mint: (
    "registry_node_cs": "1 (registry mint handler)",
    "cip_policy": "N (principal) + 1 (reference 222) — issuance_mint policy",
  ),
  withdrawals: (
    "minting_logic (ours) [RegisterAndMint] (0)",
    "issuance_logic (core) [names policy + OutputIndex proof] (0)",
  ),
  signatures: (
    "issuer",
  ),
  outputs: (
    (
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1", "ADA": "min_ada"),
      datum: (
        key: "PolicyId",
        next: "PolicyId",
        minting_logic: "Credential",
        transfer_logic: "Credential",
        third_party_logic: "Credential",
        unfracking_logic: "∅",
        global_state_cs: "∅",
      ),
    ),
    (
      name: "Tokens (principal)",
      address: "plb_addr [stake: beneficiary]",
      value: ("cip_policy": "N"),
    ),
    (
      name: "Reference token (CIP-68 222)",
      address: "plb_addr [stake: transformation_script]",
      value: ("cip_policy": "1"),
      datum: (
        metadata: "{name, ticker, terms-url, …} (CBOR)",
        version: "1",
        extra: "{schedule: [(d1,v1)…(d4,v4)], value: v0}",
      ),
    ),
  ),
  notes: [
    - Our `minting_logic` runs a single `RegisterAndMint` mode that validates BOTH concerns together — registration authority (issuer signature) + node shape, and the first-batch mint. A single arm is fine (09-DEVELOPING-SUBSTANDARDS §7); it must cross-check the tx shape (node NFT minted → node created; `cip_policy` entries present in `tx.mint`) so a caller cannot reuse it in the wrong context.
    - Minted tokens must land at a PLB output with an inline stake credential and a bounded inline datum — enforced by the protocol's `issuance_logic` (`no_escape`); the substandard does not re-check it. Supply is issuer-gated: two asset names under one policy (the principal and its CIP-68 reference), no per-holder state to mint against.
    - The CIP-68 pair is minted under the *same governed policy* (compliant: user token + reference `222`). The reference token is PLB-custodied and staked to the *transformation script* — a smart-wallet stake credential whose withdraw-0 authorizes in-place metadata updates holder-passively (T3). Its datum must fit the deployment's `max_inline_datum_bytes`: a UTxO born over the bound is frozen and unseizable.
    - The schedule is baked as validator constants — fixed 4% annual over four years, precomputed off-chain with a fixed-point scale: `[(d1, v1), (d2, v2), (d3, v3), (d4, v4)]` with `v4 ≈ 1.1699 × scale`. No on-chain compounding: the validator looks the current value up by time. The CIP-68 reference datum mirrors it for wallets and indexers; the graduation math reads the baked `v4`.
  ],
)

#figure(bond_register_issue_tx, caption: [Atomic register + first issue]) <fig:bond-register-issue>

#pagebreak()

= Tokenized bond — free transfer (T2)
_The owner can transfer the token freely at any point in its life — before and
after the deadlines. A transfer never gates who may hold or send it._

#let bond_transfer_tx = vanilla_transaction(
  "Free transfer",
  inputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: sender]",
      value: ("cip_policy": "N"),
      redeemer: [BaseSpendRedeemer { params_idx, wdrl_idx }],
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
    (
      reference: true,
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct] (0)",
    "transfer [TransferRedeemer] (0)",
    "transfer_logic (ours) (0)",
  ),
  signatures: (
    "sender",
  ),
  outputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: recipient]",
      value: ("cip_policy": "N"),
    ),
  ),
  notes: [
    - Dispatch chain: `PLB requires the dispatcher → dispatcher (TransferAct) requires transfer → transfer resolves the registry node and requires our transfer logic` (09-DEVELOPING-SUBSTANDARDS §4, §6). A transfer needs *three* script withdrawals, not two — without the dispatcher the tx fails at `programmable_logic_base` before the transfer validator ever runs.
    - The PLB spend redeemer is `BaseSpendRedeemer { params_idx, wdrl_idx }` — one record for every PLB input in the tx; it carries *no action arm*. The path is selected by the dispatcher's redeemer (`TransferAct`), never by the base redeemer.
    - Withdrawals are listed here by role; the ledger presents them in its canonical order (scripts before vkeys, ascending) — builders derive every `wdrl_idx` from the sorted set (09-DEVELOPING-SUBSTANDARDS §10).
    - P1 at every point of the lifecycle — before and after the deadlines: the permissive `transfer_logic` (Q-RULE-3) never gates who may hold or send, so the token is DEX/venue-compatible.
    - Ownership rides the inline stake credential of the token UTxO — it moves with the token at every transfer, and it is what the graduation binds the payout to (T4).
  ],
)

#figure(bond_transfer_tx, caption: [Free transfer before or after the deadlines]) <fig:bond-transfer>

#pagebreak()

= Tokenized bond — register payout key (T2b)
_A special case of the transfer: the owner spends the token to themselves and
writes a payment credential into its datum. This is the opt-in that lets someone
else (typically the issuer) graduate the token later without being able to
redirect the payout — only the owner, by signing this transfer, can set it.
An owner who intends to sign their own graduation (T4) never needs this._

#let bond_register_payout_tx = vanilla_transaction(
  "Register payout key (self-transfer)",
  inputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: owner]",
      value: ("cip_policy": "N"),
      redeemer: [BaseSpendRedeemer { params_idx, wdrl_idx }],
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
    (
      reference: true,
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct] (0)",
    "transfer [TransferRedeemer] (0)",
    "transfer_logic (ours) (0)",
  ),
  signatures: (
    "owner",
  ),
  outputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: owner]",
      value: ("cip_policy": "N"),
      datum: (
        payment_credential: "owner_payment_cred",
      ),
    ),
  ),
  notes: [
    - Same path as an ordinary transfer (T2): `programmable_logic_global [TransferAct] → transfer → transfer_logic`, owner-signed. The *only* difference is the output datum — the token returns to the same `plb_addr [stake: owner]`.
    - The datum commits the owner's payout `payment_credential`. Because the transfer is owner-signed (`authorised_stake_cred`), only the owner can set it — that is what makes it trustworthy at graduation.
    - The transfer path bounds the output datum (`max_inline_datum_bytes`) and preserves the seizable output shape (inline stake credential, no reference script), so the commitment does not freeze the token.
    - In the third-party graduation path (T4) this datum is preserved byte-for-byte, so a third party can complete the graduation but never redirect the payout.
    - Optional and re-settable: the owner may skip it (and sign the graduation directly), or overwrite it with a later self-transfer.
    - The CIP-68 metadata lives in the *reference* token, so the user token's datum is free for this commitment — the two datums never collide.
  ],
)

#figure(bond_register_payout_tx, caption: [Register payout key via owner-signed self-transfer]) <fig:bond-register-payout>

#pagebreak()

= Tokenized bond — scheduled transformation (T3)
_At each deadline the bond's value steps up 4%: the CIP-68 reference token's
datum is rewritten *in place*. The reference token is staked to the
*transformation script*, so its withdraw-0 authorizes the spend — no holder, no
issuer, no signature; anyone can submit it._

#let bond_transform_tx = vanilla_transaction(
  "Scheduled transformation (k)",
  inputs: (
    (
      name: "Reference token (CIP-68 222)",
      address: "plb_addr [stake: transformation_script]",
      value: ("cip_policy": "1"),
      datum: (
        metadata: "{…}",
        version: "1",
        extra: "{schedule, value: v_{k-1} (stale is ok)}",
      ),
      redeemer: [BaseSpendRedeemer { params_idx, wdrl_idx }],
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
    (
      reference: true,
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct] (0)",
    "transfer [TransferRedeemer] (0)",
    "transfer_logic (ours) (0)",
    "transformation_script (ours) [time gate] (0)",
  ),
  signatures: (),
  validRange: (lower: "d_k"),
  outputs: (
    (
      name: "Reference token (CIP-68 222)",
      address: "plb_addr [stake: transformation_script]",
      value: ("cip_policy": "1"),
      datum: (
        metadata: "{…}",
        version: "1",
        extra: "{schedule, value: v_k = lookup(schedule, now)}",
      ),
    ),
  ),
  notes: [
    - In-place datum change, on the *transfer path*: the reference token's stake credential is the transformation script, and `authorised_stake_cred` accepts a script owner via its withdraw-0 — which validates the schedule (`now ≥ d_k`; new value = a pure lookup of the baked constants, so a late submission jumps straight to the current step). The third-party path cannot do this: it preserves datums byte-for-byte.
    - Holder-passive and permissionless: no signatures — the issuer normally submits and the holder can force it ("if it does not change by itself").
    - The principal tokens never move — only the instrument's recorded value changes. This is how CIP-68 metadata updates reconcile with CIP-113 custody: the reference token is owned by a script, not by a holder.
    - Last evolution: after `d4` the schedule is exhausted — the script rejects any further update and the value stops. The graduation window opens at `d4` (T4).
    - The reference datum must stay within the deployment's `max_inline_datum_bytes` — keep it to the schedule and value; heavy CIP-25-style blobs would freeze the UTxO.
  ],
)

#figure(bond_transform_tx, caption: [Scheduled value transformation (+4%, in-place, holder-passive)]) <fig:bond-transform>

#pagebreak()

= Tokenized bond — deadline graduation (T4)
_From `d4` on the tokens *may* convert into the corresponding native asset at
the schedule's final value — graduation is opt-in, never forced. It is allowed
only when the payout destination is owner-authorized: the owner either signs the
graduation and names the address, or has pre-committed a payment credential into
the token's datum on an earlier owner-signed transfer (T2b). Without one the
transaction is rejected — there is no fallback, because a native asset sent to
the wrong spending key is unrecoverable. A holder who never opts in simply keeps
the (now non-transforming) token._

#let bond_graduation_tx = vanilla_transaction(
  "Deadline graduation",
  inputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "N"),
      redeemer: [BaseSpendRedeemer { params_idx, wdrl_idx }],
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
    (
      reference: true,
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  mint: (
    "cip_policy": "- N (issuance_mint policy, burn)",
    "native_policy": "N × v4 / scale (native mint policy)",
  ),
  withdrawals: (
    "spend chain — third-party path: programmable_logic_global [ThirdPartyAct] (0)",
    "spend chain — third-party path: third_party [ThirdPartyRedeemer] (0)",
    "spend chain — third-party path: third_party_logic (ours) (0)",
    "spend chain — owner path (instead): programmable_logic_global [TransferAct] (0)",
    "spend chain — owner path (instead): transfer [TransferRedeemer] (0)",
    "spend chain — owner path (instead): transfer_logic (ours) (0)",
    "burn — both paths: minting_logic (ours) [Burn] (0)",
    "burn — both paths: issuance_logic (core) [names policy] (0)",
  ),
  signatures: (),
  validRange: (lower: "d4"),
  outputs: (
    (
      name: "Ghost continuation",
      address: "plb_addr [stake: holder]",
      value: ("ADA": "min_ada"),
    ),
    (
      name: "Native asset",
      wallet: true,
      address: "owner_addr \n   [payment: owner-authorized, stake: owner]",
      value: ("native_policy": "N × v4 / scale"),
    ),
  ),
  notes: [
    - Two spend chains, one burn: a graduation runs *exactly one* spend chain — either the permissionless third-party path (`programmable_logic_global [ThirdPartyAct] → third_party → third_party_logic`) or the owner-signed transfer path (`… [TransferAct] → transfer → transfer_logic`, with the owner's signature). Both then share the *same* burn withdraw-0s — the substandard's `minting_logic [Burn]` and the core `issuance_logic` — and the same Burn-mode validation. The withdrawals list above shows both chains for reference; a real transaction carries only one.
    - A burn fires `issuance_mint` with a negative quantity — the *same two* issuance withdraw-0s as a mint (protocol `issuance_logic` + ours) — plus the full spend chain of whichever action releases the tokens (09-DEVELOPING-SUBSTANDARDS §6).
    - Event gate (Q-RULE-1): there is no separate rule script — the deadline check lives inside the substandard logic that already runs (the `third_party_logic` / `transfer_logic` withdraw-0 on the spend side and the `minting_logic` withdraw-0 on the burn side). It approves iff the validity range reaches `d4` — time-driven, no oracle; the event condition is the tx's own validity range.
    - Authorization (Q-GRAD-2, this instrument): the `d4` event gate is necessary but not sufficient — the burn also needs an *owner-authorized payout destination*. That is *either* the owner's signature (owner path, which names the destination in the tx) *or* a payment credential the owner pre-committed to the token datum (which a third party can then complete without redirecting). The permissionless third-party path therefore only works for tokens whose owners opted in beforehand; with no owner signature and no committed destination, the tx is rejected.
    - The conversion function (the Burn-mode validation) is shared by both paths: burn shape, full-burn per asset name (whole holdings burn — it makes the per-owner destination attribution exact), destination binding and the scaled native mirror. The native minting policy is signer-agnostic: it approves the mint only against the burn (`mint == burned × v4 / scale`), whichever credential signed it.
    - Companion assets are accommodated inside the PLB, under the same policy, by a CIP-68/102-aware substandard: graduation burns the principal name only, and any other governed name (the CIP-68 reference token, or an unknown one) fails closed — the companion survives a conversion and is never destroyed by it.
    - Destination binding: the native asset is a plain token at a normal `(payment_credential, stake_credential)` address, but CIP-113 attributes ownership only by the *stake* credential — the payment (spending) key is not something the framework can tie to the owner. So the payment credential must come from the owner: named in an owner-signed graduation, or pre-committed to the token's inline datum on an owner-signed transfer (T2b, preserved byte-for-byte through the third-party path, so a third party can complete but never redirect it). The stake credential stays bound to the owner's current credential.
    - No safe fallback, so no fallback: absent an owner signature *and* a committed payment credential, the transaction is rejected. Sending a native asset to an unverified spending key is unrecoverable, and graduation is optional — the owner may hold the final-value, non-transforming token indefinitely rather than convert it.
    - Native mint: exactly `burned × v4 / scale`, regardless of which credential signed the burn — the native policy approves the mint only because it is backed by the governed burn of the same name at the schedule's final value ("no burn CIP, no mint", scaled). `v4` is the baked constant (`≈ 1.1699 × scale`): the only on-chain arithmetic is this final multiply. The mint is deliberately not 1:1 quantity-conserved — the scaled value rules that out — so it is governed by the native policy and the substandard's `minting_logic` instead.
    - Third-party path mechanics: the PLB spend's paired continuation must preserve address, datum and reference script byte-for-byte (lovelace is *ratcheted* — output ≥ input, not conserved) — the *ghost* output (one-time per spent UTxO, reclaimable by the owner via a transfer-path spend). In the issuer's case the ghost remains; on the owner path (transfer path + the same Burn mode) nothing remains — the cheaper shape.
    - Base-layer guarantee: a transaction that spends a registry node can never mint or burn that node's own token — graduation is pure issuance, never mixed with a registry reconfiguration.
    - Asset identity (Q-GRAD-1): the native asset is a new policy — DEX pools / price history continuity across the flip remains an open global question.
  ],
)

#figure(bond_graduation_tx, caption: [Deadline graduation (opt-in, value-preserving)]) <fig:bond-graduation>

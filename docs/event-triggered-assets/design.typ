#import "../diagrams-template.typ": *

#show: report

= Tokenized bond — register (T0)
_The issuer registers the CIP-113 instance. The implementation enforces
*strict register-then-mint*: the registration transaction creates the node
and nothing else — the first token mint is a separate transaction (the node
cannot be resolved as a reference input in the transaction that creates it)._

#let bond_register_tx = vanilla_transaction(
  "Register",
  inputs: (
    (
      name: "Issuer funds",
      wallet: true,
      address: "issuer_addr",
      value: ("ADA": "min_ada", "FeeAsset": "f"),
    ),
  ),
  mint: (
    "registry_node_cs": "1",
  ),
  withdrawals: (
    "registry (0)",
    "issuance_logic [Register] (0)",
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
        transfer_logic: "Credential (permissive)",
        third_party_logic: "Credential (governed extraction)",
        global_state_cs: "∅",
        protected_prefixes: "[]",
      ),
    ),
  ),
  notes: [
    - Strict register-then-mint (reference implementation, Q-GRAD-2): the `Register` mode requires an empty governed mint; the `Mint` mode requires the node as a reference input — one transaction cannot do both.
    - Registry registration pins the frozen stance (Q-RULE-2/3): permissive transfer logic, governed-extraction third-party logic, no global state, no protected prefixes. The substandard reference validators are used as-is.
    - Validator params fixed here: `rule` = the graduation rule script's hash (Q-RULE-1); `graduated_policy` = `None` — the final conversion mints the schedule's appreciated value, so the reference 1:1 quantity conservation does not apply (see T4).
  ],
)

#figure(bond_register_tx, caption: [Register the CIP-113 instance]) <fig:bond-register>

#pagebreak()

= Tokenized bond — issue (T1)
_The issuer mints the CIP-113 tokens for a beneficiary (single asset name, no
per-holder state) and publishes the instrument's terms as a CIP-68-style
reference datum: the value schedule (four annual deadlines, +4% each) lives in
validator constants and is mirrored in the reference datum for wallets and
indexers._

#let bond_issue_tx = vanilla_transaction(
  "Issue to beneficiary",
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
    (
      reference: true,
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  mint: (
    "cip_policy": "N",
    "terms_policy": "1 (reference token, CIP-68 style)",
  ),
  withdrawals: (
    "issuance_mint (core)",
    "issuance_logic [Mint] (0)",
  ),
  signatures: (
    "issuer",
  ),
  outputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: beneficiary]",
      value: ("cip_policy": "N"),
    ),
    (
      name: "Terms (reference datum)",
      address: "terms_addr (bond terms script)",
      value: ("ADA": "min_ada", "terms_policy": "1"),
      datum: (
        schedule: "[(d1, v1), (d2, v2), (d3, v3), (d4, v4)]",
        value: "v0 (initial)",
      ),
    ),
  ),
  notes: [
    - Supply is issuer-gated: any positive governed mint is the issuance `Mint` mode (issuer-signed). Single asset name — there is no per-holder state to mint against.
    - The reference token is minted under the *terms policy* (the bond's own script), deliberately *not* under the governed policy: every governed token is PLB-custodied, and the third-party path preserves datums byte-for-byte — a reference datum under the governed policy could never be updated without the holder's signature.
    - The schedule is baked as validator constants — fixed 4% annual over four years, precomputed off-chain with a fixed-point scale: `[(d1, v1), (d2, v2), (d3, v3), (d4, v4)]` with `v4 ≈ 1.1699 × scale`. No on-chain compounding: the validator looks the current value up by time. The datum is the CIP-68 display mirror; the graduation math reads the baked `v4`.
    - The CIP-113 tokens carry no datum: the substandard never reads one — the instrument's condition lives in time (the validity range) and in the terms constants, not in state.
  ],
)

#figure(bond_issue_tx, caption: [Issue CIP tokens and publish the terms datum]) <fig:bond-issue>

#pagebreak()

= Tokenized bond — free transfer (T2)
_Before and after the deadlines the owner transfers freely (P1). Conversion is
never a freeze: an unconverted token keeps moving the same way._

#let bond_transfer_tx = vanilla_transaction(
  "Free transfer",
  inputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: sender]",
      value: ("cip_policy": "N"),
      redeemer: [SpendViaTransfer],
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
    "transfer (0)",
    "transfer_logic (0)",
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
    - P1 at every point of the lifecycle — before and after the deadlines: the permissive `transfer_logic` (Q-RULE-3) never gates who may hold or send, so the token is DEX/venue-compatible.
    - Ownership rides the inline stake credential of the token UTxO — it moves with the token at every transfer, and it is what the graduation binds the payout to (T4).
    - No burn, no issuance, no rule withdraw-0: a transfer never touches the instrument's condition — the schedule lives in time and constants, not in any state.
  ],
)

#figure(bond_transfer_tx, caption: [Free transfer before or after the deadlines]) <fig:bond-transfer>

#pagebreak()

= Tokenized bond — scheduled transformation (T3)
_At each deadline the instrument's value inflates 4%: a transaction updates the
terms datum to the schedule's current value. The holder does nothing — the
issuer normally submits it, and anyone (including the holder) can force it,
because no signature is required._

#let bond_transform_tx = vanilla_transaction(
  "Scheduled transformation (k)",
  inputs: (
    (
      name: "Terms (reference datum)",
      address: "terms_addr (bond terms script)",
      value: ("ADA": "min_ada", "terms_policy": "1"),
      datum: (
        schedule: "[(d1, v1), (d2, v2), (d3, v3), (d4, v4)]",
        value: "v_{k-1} (stale is ok)",
      ),
      redeemer: [transform (k)],
    ),
  ),
  signatures: (),
  validRange: (lower: "d_k"),
  outputs: (
    (
      name: "Terms (reference datum)",
      address: "terms_addr (bond terms script)",
      value: ("ADA": "min_ada", "terms_policy": "1"),
      datum: (
        schedule: "[(d1, v1), (d2, v2), (d3, v3), (d4, v4)]",
        value: "v_k = lookup(schedule, now)",
      ),
    ),
  ),
  notes: [
    - Time-gated, permissionless: the terms script approves the update iff the validity range reaches `d_k`, and the new datum is the schedule's current value — a pure lookup of the baked constants (no on-chain compounding, no rounding drift; a late submission jumps straight to the current step). No signatures: the issuer normally submits and the holder can force it ("if it does not change by itself").
    - No PLB involvement: the transformation never spends a programmable token — no ghost outputs, no CIP-113 machinery, no owner action. The tokens stay where they are; only the instrument's recorded value moves.
    - Last evolution: after `d4` the schedule is exhausted — the script rejects any further update and the value stops ("al cuarto año no hay más POSIX"). The graduation window opens at `d4` (T4).
    - CIP-68 pattern: the reference token carries the instrument's metadata at the bond's own terms script; wallets and indexers read the current value from it, while the graduation math is derived from the validator constants.
  ],
)

#figure(bond_transform_tx, caption: [Scheduled value transformation (+4%, holder-passive)]) <fig:bond-transform>

#pagebreak()

= Tokenized bond — deadline graduation (T4)
_From `d4` on, *anyone* may convert the CIP-113 tokens into the corresponding
native asset at the schedule's final value — third-party path, *no owner
signature*. The conversion is value-preserving and destination-bound, so
there is no attack or benefit in waiting, and the holder does nothing._

#let bond_graduation_tx = vanilla_transaction(
  "Deadline graduation",
  inputs: (
    (
      name: "Tokens",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "N"),
      redeemer: [SpendViaThirdParty],
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
    "cip_policy": "-N",
    "native_policy": "+N × v4 / scale",
  ),
  withdrawals: (
    "third_party (0)",
    "third_party_logic (0)",
    "graduation_rule [Graduate] (0)",
    "issuance_mint (core)",
    "issuance_logic [Burn] (0)",
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
      address: "owner_staked_addr",
      value: ("native_policy": "N × v4 / scale"),
    ),
  ),
  notes: [
    - Event gate (Q-RULE-1): the rule withdraw-0 (`Graduate`) approves iff the validity range reaches `d4` — time-driven, no oracle; the event condition is the tx's own validity range.
    - Authority stance (Q-GRAD-2, this instrument): *event-gated only* — no owner consent, anyone may assemble and submit (the submitter pays the fees). This requires a Burn-mode variant without the reference validator's `owner_authorized` check (a fork of the final validator's Burn wiring — the declared customization point). It is sound because the conversion is value-preserving and destination-bound; instruments where conversion is *not* value-preserving (e.g. carbon-credit retirement, verified by an entity) must carry their authority in the rule `Credential` instead.
    - Destination binding: the natives must land in outputs whose address carries the burned token's inline stake credential — the owner's current credential, which moves with the token at every transfer. No owner registry and no extra transaction are needed. Delivery goes to the owner's staked wallet; a holder may stamp a payment address into their datum (owner-signed, self-trustworthy) for finer delivery.
    - Native mint: exactly `burned × v4 / scale` — the native policy approves the mint only because it is backed by the governed burn of the same name at the schedule's final value ("no burn CIP, no mint", scaled). `v4` is the baked constant (`≈ 1.1699 × scale`): the only on-chain arithmetic is this final multiply. `graduated_policy: None`: the reference 1:1 quantity conservation would forbid the scaled mint, so the mint is governed by the native policy and the rule script instead.
    - Third-party path mechanics: the PLB spend's paired continuation must preserve address, datum and reference script byte-for-byte — the *ghost* output (one-time per spent UTxO, reclaimable by the owner via a transfer-path spend). The holder-signed variant (`SpendViaTransfer` + the same Burn mode) skips the third-party dispatch and is the cheaper shape.
    - Base-layer guarantee: a transaction that spends a registry node can never mint or burn that node's own token — graduation is pure issuance, never mixed with a registry reconfiguration.
    - Asset identity (Q-GRAD-1): the native asset is a new policy — DEX pools / price history continuity across the flip remains an open global question.
  ],
)

#figure(bond_graduation_tx, caption: [Deadline graduation (permissionless, value-preserving)]) <fig:bond-graduation>

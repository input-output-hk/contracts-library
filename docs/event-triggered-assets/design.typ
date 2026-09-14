#import "../diagrams-template.typ": *

#show: report

= Tokenized bond — issue (T0)
_The minimal P2 (time constraint) + P3 instantiation (the use case at hand): the issuer
mints CIP-113 tokens for a beneficiary. Before the deadline the owner transfers
them freely (P1); after it, the tokens convert 1:1 into a plain native asset
with the owner's consent (P3). One asset name, no per-holder state: the single
event — the deadline — lives in the validity range of the graduating
transaction._

#let deadline_issue_tx = vanilla_transaction(
  "Issue to beneficiary",
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
    "cip_policy": "N",
  ),
  withdrawals: (
    "registry (0)",
    "issuance_logic [Mint] (0)",
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
    (
      name: "Tokens",
      address: "plb_addr [stake: beneficiary]",
      value: ("cip_policy": "N"),
    ),
  ),
  notes: [
    - Registry registration pins the frozen stance (Q-RULE-2/3): permissive transfer logic, governed-extraction third-party logic, no global state, no protected prefixes. The substandard reference validators are used as-is.
  ],
)

#figure(deadline_issue_tx, caption: [Issue CIP tokens to the beneficiary]) <fig:deadline-issue>

#pagebreak()

= Tokenized bond — free transfer (T1)
_Before the deadline the owner transfers freely (P1) — the generic permissive
transfer path applies verbatim. Conversion is never a freeze: past the
deadline an unconverted token keeps moving the same way._

#let deadline_transfer_tx = vanilla_transaction(
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
    - P1 at every point of the lifecycle — before and after the deadline: the permissive `transfer_logic` (Q-RULE-3) never gates who may hold or send, so the token is DEX/venue-compatible.
  ],
)

#figure(deadline_transfer_tx, caption: [Free transfer before (or after) the deadline]) <fig:deadline-transfer>

#pagebreak()

= Tokenized bond — deadline graduation (T2)
_After the deadline the issuer (as the assembling keeper) may convert the CIP
tokens into the corresponding native asset — third-party path, owner-signed.
The deadline rule approves the event condition; the issuance `Burn` mode
enforces the owner's consent; the native policy mints 1:1 against the burn._

#let deadline_graduation_tx = vanilla_transaction(
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
    "native_policy": "+N",
  ),
  withdrawals: (
    "third_party (0)",
    "third_party_logic (0)",
    "deadline_rule [Graduate] (0)",
    "issuance_mint (core)",
    "issuance_logic [Burn] (0)",
  ),
  signatures: (
    "keeper (assembles)",
    "holder (consent)",
  ),
  validRange: (lower: "deadline"),
  outputs: (
    (
      name: "Ghost continuation",
      address: "plb_addr [stake: holder]",
      value: ("ADA": "min_ada"),
    ),
    (
      name: "Native asset",
      wallet: true,
      address: "holder_addr",
      value: ("native_policy": "N"),
    ),
  ),
  notes: [
    - Deadline gate (Q-RULE-1): the rule withdraw-0 (`Graduate`) approves iff the validity range reaches the deadline (`now ≥ deadline`) — time-driven, no oracle; the event condition is the tx's own validity range.
    - Owner consent is structural (Q-GRAD-2): every burned token's inline stake credential must sign (or run its withdraw-0). The issuer assembles and submits, but nothing burns without the owner's signature — "the issuer may convert, with the owner's consent", on-chain.
    - No burn CIP, no mint: the native policy approves the mint only because it is backed by the governed burn of the same name and quantity; the issuance `Burn` mode mirrors it (`graduated_conservation`) — every burned CIP gets its native token, and only that one (Q-GRAD-1, per-holder migration).
    - Third-party path mechanics: the PLB spend's paired continuation must preserve address, datum and reference script byte-for-byte — the *ghost* output (same stake credential, no CIP tokens; its datum is a byte-identical copy of the input's, empty here). Extraction is the only real effect. The holder-signed variant (`SpendViaTransfer` + the same `Burn` mode) skips the third-party dispatch and is the cheaper shape; the third-party form is chosen here to match the stated authority.
    - Base-layer guarantee: a transaction that spends a registry node can never mint or burn that node's own token — graduation is pure issuance, never mixed with a registry reconfiguration.
    - Asset identity (Q-GRAD-1): the native asset is a new policy — DEX pools / price history continuity across the flip remains an open global question.
  ],
)

#figure(
  deadline_graduation_tx,
  caption: [Deadline graduation (keeper-assembled, owner-signed)],
) <fig:deadline-graduation>

#import "../diagrams-template.typ": *

#show: report

= Tokenized bond — register (T0)
_The issuer creates the instrument's registry entry. The vault is assumed
already created and funded by the owner (out of scope), and no certificate is
minted here — the same register serves every later deposit._

#let bond_register_tx = vanilla_transaction(
  "Register",
  inputs: (
    (
      name: "Issuer funds",
      wallet: true,
      address: "issuer_addr",
      value: ("ada": "min_ada", "FeeAsset": "f"),
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
  ),
  mint: (
    "registry_node_cs": "1 (registry mint handler)",
  ),
  withdrawals: (
    "minting_logic (ours) [Register]",
    "issuance_logic (core) [names policy + OutputIndex proof]",
  ),
  signatures: (
    "issuer",
  ),
  outputs: (
    (
      name: "RegistryNode",
      address: "registry_addr",
      value: ("registry_node_cs": "1"),
    ),
  ),
  notes: [
    - The issuer registers the instrument once: the RegistryNode pins the governed `cip_policy` and the transfer / minting logic stance, with the schedule baked into the validators. No reference NFT is minted here, so the instrument is reusable.
    - The ADA vault is assumed already created and funded by the owner (company/country); its creation, funding and the owner's custody are out of scope — see spec §7.
    - The governed `cip_policy` is resolved at runtime from the RegistryNode, so it is never baked into the minting logic's parameters.
  ],
)

#figure(bond_register_tx, caption: [Register: the issuer pins the instrument once; deposits can follow]) <fig:bond-register>

#pagebreak()

= Tokenized bond — deposit (unit)
_Anyone deposits one bond unit: the principal ADA moves into the vault and the
same transaction mints that depositor's CIP-113 reference NFT, recording the
published terms and an initial `step: 0`._

#let bond_deposit_tx = vanilla_transaction(
  "Deposit (unit)",
  inputs: (
    (
      name: "Depositor funds",
      wallet: true,
      address: "depositor_addr",
      value: ("ada": "principal + min_ada", "FeeAsset": "f"),
    ),
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
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
    "cip_policy": "1 (reference NFT) — issuance_mint [Deposit]",
  ),
  withdrawals: (
    "minting_logic (ours) [Deposit]",
    "issuance_logic (core) [names policy + RegistryNode]",
  ),
  signatures: (
    "depositor",
  ),
  outputs: (
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds + principal"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
    ),
    (
      name: "Reference NFT",
      address: "plb_addr [stake: depositor]",
      value: ("cip_policy": "1"),
      datum: (
        step: "0",
      ),
    ),
  ),
  notes: [
    - The deposit is permissionless and per unit: the minting logic admits the certificate only when the vault's net ADA gain equals exactly the unit `principal`, so the certificate and its backing exist atomically (I6). No authority signature is needed — the depositor signs only to spend their own funds.
    - The reference NFT is the instrument's only CIP-113 token; one certificate is minted per deposit, so many holders share the same registered schedule and advance their own `step`.
    - Coupons are plain native assets minted later by the coupon policy; nothing else is minted here.
  ],
)

#figure(bond_deposit_tx, caption: [Deposit: one unit of principal into the vault, one reference NFT to the depositor]) <fig:bond-deposit>

#pagebreak()

= Tokenized bond — transfer (T1)
_The holder moves the certificate freely; the transfer logic only enforces that
the claim state never rewinds — its `step` stays the same._

#let bond_transfer_tx = vanilla_transaction(
  "Transfer",
  inputs: (
    (
      name: "Reference NFT",
      address: "plb_addr [stake: sender]",
      value: ("cip_policy": "1"),
      datum: (
        step: "k",
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
    "programmable_logic_global [TransferAct]",
    "transfer [TransferRedeemer]",
    "transfer_logic (ours)",
  ),
  signatures: (
    "sender",
  ),
  outputs: (
    (
      name: "Reference NFT",
      address: "plb_addr [stake: recipient]",
      value: ("cip_policy": "1"),
      datum: (
        step: "k",
      ),
    ),
  ),
  notes: [
    - Ownership rides the certificate's inline stake credential: moving the token moves the claim on that unit's remaining coupons and principal, and the datum (just `step`) is carried across unchanged.
    - The transfer logic resolves the governed `cip_policy` from the RegistryNode and enforces step monotonicity (I7): with a continuation, `step` must stay or advance by exactly one — never decrease. A plain transfer preserves it, so a claimed step cannot be rewound and re-claimed.
    - At most one certificate per transaction. The coupon claim page (next) is the admitted advance (`step: k - 1 → k`); retirement is a `cip_policy` burn on the graduation page.
  ],
)

#figure(bond_transfer_tx, caption: [Transfer: the certificate moves, the claim state never rewinds]) <fig:bond-transfer>

#pagebreak()

= Tokenized bond — coupon claim (step k)
_At each deadline the holder claims the step's coupon. The claim spends and
re-outputs the reference NFT, advancing its `step` so no step can be claimed
twice._

#let bond_coupon_claim_tx = vanilla_transaction(
  "Coupon claim (k)",
  inputs: (
    (
      name: "Reference NFT",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "1"),
      datum: (
        step: "k - 1",
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
  mint: (
    "cNt_policy": "1 unit, asset name = amount_k (decimal lovelace)",
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct]",
    "transfer [TransferRedeemer]",
    "transfer_logic (ours)",
  ),
  signatures: (
    "holder",
  ),
  outputs: (
    (
      name: "Coupon",
      address: "holder_payment_addr",
      value: ("cNt_policy": "1 × {name: amount_k}"),
    ),
    (
      name: "Reference NFT",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "1"),
      datum: (
        step: "k",
      ),
    ),
  ),
  validRange: (lower: "d_k"),
  notes: [
    - The coupon policy admits the mint only when the validity range reaches `d_k` *and* the spent reference NFT records `step: k - 1`; the continuation records `step: k`, the only advance the transfer logic admits. That anchor makes each step claimable exactly once per certificate.
    - The coupon is a native asset whose *name is its value*: name `"1124"` is worth 1124 lovelace. Two steps of equal amount share a name and are fungible on purpose.
    - The claim is an owner-signed PLB spend of the reference NFT; it never touches the vault.
  ],
)

#figure(bond_coupon_claim_tx, caption: [Coupon claim at step k (holder-signed, step-anchored)]) <fig:bond-coupon-claim>

#pagebreak()

= Tokenized bond — redemption (burn-to-pay)
_A coupon is redeemed by burning it at the vault: the vault validator pays out
exactly the ADA the burned coupons name, and nothing else leaves._

#let bond_redeem_tx = vanilla_transaction(
  "Redemption (burn-to-pay)",
  inputs: (
    (
      name: "Coupon",
      address: "holder_addr",
      value: ("cNt_policy": "1 × {name: amount}"),
      redeemer: [Redeem { payouts }],
    ),
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
    ),
  ),
  mint: (
    "cNt_policy": "- 1 (coupon burned)",
  ),
  signatures: (
    "redeemer",
  ),
  outputs: (
    (
      name: "Payout",
      wallet: true,
      address: "redeemer-named_addr",
      value: ("ada": "Σ decode(name) × burned"),
    ),
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds - Σ decode(name) × burned"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
    ),
  ),
  notes: [
    - The vault validator sums `decode(name) × burned_quantity` over the negative coupon mints and requires the vault's net ADA loss to equal that sum exactly. A redeemer cannot ask for more than the coupons are worth, and the vault cannot short-pay.
    - The payout goes to the address(es) the redeemer names in the same transaction.
    - Redemption burns the coupon, so no coupon is ever paid twice.
    - No owner signature is needed on this path; the burn-to-pay rule is enforced on-chain.
  ],
)

#figure(bond_redeem_tx, caption: [Redemption: burn coupons, the vault pays exactly what they name]) <fig:bond-redeem>

#pagebreak()

= Tokenized bond — graduation (T4)
_From `d4` on the holder claims the principal-only coupon and retires the
reference NFT. The principal is the deployment's baked unit amount._

#let bond_graduation_tx = vanilla_transaction(
  "Graduation",
  inputs: (
    (
      name: "Reference NFT",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "1"),
      datum: (
        step: "final",
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
  mint: (
    "cip_policy": "- 1 (certificate retired) — issuance_mint [Retire]",
    "cNt_policy": "1 unit, asset name = principal (decimal lovelace)",
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct]",
    "transfer [TransferRedeemer]",
    "transfer_logic (ours)",
    "minting_logic (ours) [Retire]",
    "issuance_logic (core) [names policy + RegistryNode]",
  ),
  signatures: (
    "holder",
  ),
  outputs: (
    (
      name: "Principal coupon",
      address: "holder_payment_addr",
      value: ("cNt_policy": "1 × {name: principal}"),
    ),
  ),
  validRange: (lower: "d4"),
  notes: [
    - The principal is the deployment's baked unit amount, so the graduation cannot over- or under-claim.
    - The reference NFT is *retired* by a `cip_policy` burn at its final `step` within the `d4` window — the issuance logic's `Retire` mode validates the burn shape and payout, and the transfer logic admits no continuation on this shape only.
    - The principal coupon is then redeemed at the vault like any other coupon (see the redemption page): burn it, the vault pays the principal.
  ],
)

#figure(bond_graduation_tx, caption: [Graduation: claim the principal-only coupon, retire the reference NFT]) <fig:bond-graduation>

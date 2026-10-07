#import "../diagrams-template.typ": *

#show: report

= Tokenized bond — register + deposit (T0)
_The first transaction: the holder deposits the principal ADA into the vault and
the instrument mints the single CIP-113 reference NFT to the holder, recording
the published terms and an initial `step: 0`._

#let bond_register_deposit_tx = vanilla_transaction(
  "Register + deposit",
  inputs: (
    (
      name: "User funds",
      wallet: true,
      address: "user_addr",
      value: ("ada": "principal + min_ada", "FeeAsset": "f"),
    ),
    (
      reference: true,
      name: "Protocol params",
      address: "protocol_params",
    ),
  ),
  mint: (
    "registry_node_cs": "1 (registry mint handler)",
    "cip_policy": "1 (reference NFT) — issuance_mint policy",
  ),
  withdrawals: (
    "minting_logic (ours) [RegisterAndMint] (0)",
    "issuance_logic (core) [names policy + OutputIndex proof] (0)",
  ),
  signatures: (
    "holder",
  ),
  outputs: (
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "existing_funds + principal"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
    ),
    (
      name: "Reference NFT",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "1"),
      datum: (
        metadata: "{name, ticker, terms-url, …} (CBOR)",
        schedule: "[(d1,a1)…(d4,a4)]",
        principal: "principal (ADA)",
        step: "0",
      ),
    ),
  ),
  notes: [
    - The deposit and the reference-NFT mint happen atomically: the certificate and its backing exist together. The vault is assumed already funded by the owner (company/country); the holder's deposit sits on top of those funds.
    - The reference NFT is the *only* CIP-113 token. It is holder-staked at the PLB and carries the instrument's published terms plus the last-claimed `step`.
    - Coupons are plain native assets minted later by the coupon policy; nothing else is minted here.
  ],
)

#figure(bond_register_deposit_tx, caption: [Register + deposit: principal into the vault, reference NFT to the holder]) <fig:bond-register-deposit>

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
        schedule: "[(d1,a1)…(d4,a4)]",
        principal: "principal (ADA)",
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
    "programmable_logic_global [TransferAct] (0)",
    "transfer [TransferRedeemer] (0)",
    "transfer_logic (ours) (0)",
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
        schedule: "[(d1,a1)…(d4,a4)]",
        principal: "principal (ADA)",
        step: "k",
      ),
    ),
  ),
  validRange: (lower: "d_k"),
  notes: [
    - The coupon policy admits the mint only when the validity range reaches `d_k` *and* the spent reference NFT records `step: k - 1`; the continuation records `step: k`. That anchor makes each step claimable exactly once.
    - The coupon is a native asset whose **name is its value**: name `"1124"` is worth 1124 lovelace. Two steps of equal amount share a name and are fungible on purpose.
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

= Tokenized bond — owner extract
_The company/country's unconditional custody path: the owner may move any ADA
out of the vault at any time._

#let bond_owner_extract_tx = vanilla_transaction(
  "Owner extract",
  inputs: (
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
      redeemer: [OwnerExtract],
    ),
  ),
  signatures: (
    "owner (company/country)",
  ),
  outputs: (
    (
      name: "Payout",
      wallet: true,
      address: "owner_addr",
      value: ("ada": "any amount"),
    ),
    (
      name: "Vault",
      address: "vault_addr",
      value: ("ada": "funds - extracted"),
      datum: (
        owner: "company/country (signing credential)",
        cnt_policy: "coupon policy id",
      ),
    ),
  ),
  notes: [
    - `OwnerExtract` is approved purely by the owner's signature: the owner may move any amount at any time. This is the instrument's explicit custody assumption — holders trust the owner and the vault's solvency.
    - The `Redeem` path (previous page) is separate and needs no owner signature.
  ],
)

#figure(bond_owner_extract_tx, caption: [Owner extract: the company/country's custody path]) <fig:bond-owner-extract>

#pagebreak()

= Tokenized bond — graduation (T4)
_From `d4` on the holder claims the principal-only coupon and retires the
reference NFT. The principal is read from the certificate's datum._

#let bond_graduation_tx = vanilla_transaction(
  "Graduation",
  inputs: (
    (
      name: "Reference NFT",
      address: "plb_addr [stake: holder]",
      value: ("cip_policy": "1"),
      datum: (
        schedule: "[(d1,a1)…(d4,a4)]",
        principal: "principal (ADA)",
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
    "cNt_policy": "1 unit, asset name = principal (decimal lovelace)",
  ),
  withdrawals: (
    "programmable_logic_global [TransferAct] (0)",
    "transfer [TransferRedeemer] (0)",
    "transfer_logic (ours) (0)",
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
    - The principal amount comes from the reference NFT's datum, so the graduation cannot over- or under-claim.
    - The reference NFT is **retired** here (burned or spent with no continuation) — it is the instrument's certificate and its life ends at graduation.
    - The principal coupon is then redeemed at the vault like any other coupon (2 pages back): burn it, the vault pays the principal.
  ],
)

#figure(bond_graduation_tx, caption: [Graduation: claim the principal-only coupon, retire the reference NFT]) <fig:bond-graduation>

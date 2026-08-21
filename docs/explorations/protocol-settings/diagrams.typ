#import "../diagrams-template.typ": *

#show: report

= Launch settings

#let launch_tx = vanilla_transaction(
  "",
  inputs: (
    (
      name: "Seed UTxO",
      // wallet: true,
      // address: "creator_addr",
      // value: ("ADA": "min_ada", "SetupFeeAsset": "s"),
    ),
  ),
  mint: (
    "Settings NFT": 1,
  ),
  withdrawals: (
    "apply_auth",
  ),
  outputs: (
    (
      name: "Settings UTxO",
      address: "settings_addr",
      value: (
        "Settings NFT": "1",
        // "ADA": "min_ada",
      ),
      datum: (
        // current: "Data",
        // next: "Option(Data)",
        current: [*data*],
        next: [None],
        next_apply: [None],
      ),
    ),
  ),
  notes: [
    - `settings_addr`: payment is `settings_hash`, staking is any
    - `settings_nft`: policy is `settings_hash`, token name is `settings_token_name`
    - `settings_hash = hash(settings_validator(seed_utxo, propose_auth, apply_auth, apply_delay, settings_token_name))`
    - `data`: the settings data. it is such that `validate_datum(data)` is true
  ],
)

#figure(launch_tx, caption: [Launch settings transaction]) <fig:launch>


= Propose settings

#let propose_tx = vanilla_transaction(
  "",
  inputs: (
    (
      name: "Settings UTxO",
      address: "settings_addr",
      value: (
        "Settings NFT": "1",
        // "ADA": "min_ada",
      ),
      datum: (
        // current: "Data",
        // next: "Option(Data)",
        current: [data],
        next: [maybe_data],
        next_apply: [maybe_timestamp],
      ),
    ),
  ),
  withdrawals: (
    "propose_auth",
  ),
  outputs: (
    (
      name: "Settings UTxO",
      address: "settings_addr",
      value: (
        "Settings NFT": "1",
        // "ADA": "min_ada",
      ),
      datum: (
        // current: "Data",
        // next: "Option(Data)",
        current: [data],
        next: [*proposed*],
        next_apply: [*timestamp*],
      ),
    ),
  ),
  notes: [
    - `settings_addr`: payment is `settings_hash`, staking is any
    - `settings_nft`: policy is `settings_hash`, token name is `settings_token_name`
    - `settings_hash = hash(settings_validator(seed_utxo, propose_auth, apply_auth, apply_delay, settings_token_name))`
    - `maybe_data`: can be `None` or `Some(data)`
    - `proposed`: the proposed settings data. it is such that `validate_datum(proposed)` is true
    - `timestamp = now + apply_delay`, where `apply_delay` is the minimum time that must pass before the proposed settings can be applied
  ],
)

#figure(propose_tx, caption: [Propose settings transaction]) <fig:propose>


= Apply settings

#let apply_tx = vanilla_transaction(
  "",
  inputs: (
    (
      name: "Settings UTxO",
      address: "settings_addr",
      value: (
        "Settings NFT": "1",
        // "ADA": "min_ada",
      ),
      datum: (
        // current: "Data",
        // next: "Option(Data)",
        current: [data1],
        next: [data2],
        next_apply: [timestamp],
      ),
    ),
  ),
  withdrawals: (
    "apply_auth",
  ),
  outputs: (
    (
      name: "Settings UTxO",
      address: "settings_addr",
      value: (
        "Settings NFT": "1",
        // "ADA": "min_ada",
      ),
      datum: (
        // current: "Data",
        // next: "Option(Data)",
        current: [*data2*],
        next: [*None*],
        next_apply: [*None*],
      ),
    ),
  ),
  notes: [
    - `settings_addr`: payment is `settings_hash`, staking is any
    - `settings_nft`: policy is `settings_hash`, token name is `settings_token_name`
    - `settings_hash = hash(settings_validator(seed_utxo, propose_auth, apply_auth, apply_delay))`
    - delay must have expired: `now >= timestamp`
  ],
)

#figure(apply_tx, caption: [Apply settings transaction]) <fig:apply>



#pagebreak()

#import "../diagrams-template.typ": *

#show: report

= Market genesis (Mint Beacon)
_Creates a new market by minting a single beacon and locking it in the outcome
UTxO with the winner `None`. One beacon exists per `market_id`._

#let genesis_tx = vanilla_transaction(
  "Market Genesis",
  inputs: (
    (
      name: "Creator funds",
      wallet: true,
      address: "creator_addr",
      value: ("ADA": "min_ada", "SetupFeeAsset": "s"),
    ),
  ),
  mint: (
    "Beacon": 1,
  ),
  outputs: (
    (
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1", "ADA": "min_ada"),
      datum: (
        market_id: "ByteArray",
        winner: [_None_],
        outcome_credential: "Credential",
        cutoff: "PosixTime",
        resolution_timeout: "PosixTime",
        claim_timeout: "PosixTime",
        collateral: "TokenInfo",
      ),
    ),
    (
      name: "Setup fee",
      wallet: true,
      address: "market_address",
      value: ("SetupFeeAsset": "s"),
    ),
  ),
  notes: [
    - `MintBeacon { market_id }` mints exactly 1 beacon for the market.
    - The beacon uniquely authenticates this market's outcome UTxO.
  ],
)

#figure(genesis_tx, caption: [Market genesis transaction]) <fig:genesis>

#pagebreak()

= Take position (Mint Complete Set)
_A participant locks N collateral and mints N YES + N NO. Only allowed before cutoff._

#let mint_set_tx = vanilla_transaction(
  "Mint Complete Set",
  inputs: (
    (
      name: "Bettor funds",
      wallet: true,
      address: "bettor_addr",
      value: ("Collateral": "N", "MarketFeeAsset": "m"),
    ),
    (
      reference: true,
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [_None_],
        cutoff: "PosixTime",
        collateral: "TokenInfo",
        "...": [],
      ),
    ),
  ),
  mint: (
    "YES_market_id": "N",
    "NO_market_id": "N",
  ),
  validRange: (upper: "cutoff"),
  outputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
    ),
    (
      name: "Bettor payout",
      wallet: true,
      address: "bettor_addr",
      value: ("YES_market_id": "N", "NO_market_id": "N"),
    ),
  ),
  notes: [
    - `MintSet { market_id }` mints equal quantities of YES and NO.
    - `collateral_unit` is read from the outcome reference input.
    - Time-gating (validity range #sym.lt.eq cutoff) prevents fabricating a
      winning position after resolution.
  ],
)

#figure(mint_set_tx, caption: [Mint complete set transaction]) <fig:mint-set>

#pagebreak()

= Exit before resolution (Burn Complete Set)
_A participant returns a complete set (equal YES + NO) for collateral before the
market resolves._

#let burn_set_tx = vanilla_transaction(
  "Burn Complete Set",
  inputs: (
    (
      name: "Bettor set",
      wallet: true,
      address: "bettor_addr",
      value: ("YES_market_id": "k", "NO_market_id": "k", "MarketFeeAsset": "m"),
    ),
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [BurnSet],
    ),
    (
      reference: true,
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [_None_],
        collateral: "TokenInfo",
        resolution_timeout: "PosixTime",
        "...": [],
      ),
    ),
  ),
  mint: (
    "YES_market_id": "-k",
    "NO_market_id": "-k",
  ),
  validRange: (upper: "resolution_timeout"),
  outputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N - k", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
    ),
    (
      name: "Bettor refund",
      wallet: true,
      address: "bettor_addr",
      value: ("Collateral": "k"),
    ),
  ),
  notes: [
    - `collateral_unit` is read from the outcome reference input.
    - `BurnSet { market_id }` burns equal YES and NO quantities.
  ],
)

#figure(burn_set_tx, caption: [Burn complete set transaction]) <fig:burn-set>

#pagebreak()

= Resolve outcome
_The resolution authority declares the winning outcome. The beacon and all datum
fields except `winner` are preserved in a continuation UTxO._

#let resolve_tx = vanilla_transaction(
  "Resolve",
  inputs: (
    (
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [_None_],
        outcome_credential: "Credential",
        cutoff: "PosixTime",
        resolution_timeout: "PosixTime",
        claim_timeout: "PosixTime",
        collateral: "TokenInfo",
      ),
      redeemer: [Resolve { winner }],
    ),
  ),
  validRange: (upper: "resolution_timeout"),
  signatures: (
    [`outcome_credential`],
  ),
  outputs: (
    (
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [*Yes / No / Draw*],
        outcome_credential: "Credential",
        cutoff: "PosixTime",
        resolution_timeout: "PosixTime",
        claim_timeout: "PosixTime",
        collateral: "TokenInfo",
      ),
    ),
  ),
  notes: [
    - Requires authorization by `outcome_credential`.
    - Only `winner` may change; all other datum fields and the beacon are
      preserved.
  ],
)

#figure(resolve_tx, caption: [Resolve transaction]) <fig:resolve>

#pagebreak()

= Redeem winner
_After a YES/NO resolution, the holder of the winning tokens burns them for 1 collateral
each. The outcome UTxO is read as a reference input to learn the winner._

#let redeem_tx = vanilla_transaction(
  "Redeem Winner",
  inputs: (
    (
      reference: true,
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [*Yes*],
        collateral: "TokenInfo",
        "...": [],
      ),
    ),
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [RedeemWinner],
    ),
    (
      name: "Winner tokens",
      wallet: true,
      address: "bettor_addr",
      value: ("YES_market_id": "k", "MarketFeeAsset": "m"),
    ),
  ),
  mint: (
    "YES_market_id": "-k",
  ),
  outputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N - k", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [RedeemWinner],
    ),
    (
      name: "Winner payout",
      wallet: true,
      address: "bettor_addr",
      value: ("Collateral": "k"),
    ),
  ),
  notes: [
    - `RedeemWinner` burns only the winning token.
  ],
)

#figure(redeem_tx, caption: [Redeem winner transaction]) <fig:redeem>

#pagebreak()

= Refund on Draw (Claim Draw)
_When the market resolves to a `Draw`, every participant refunds by burning any amount of YES/NO tokens for half collateral each (before `claim_timeout`)._

#let refund_tx = vanilla_transaction(
  "Refund Draw (Claim Draw)",
  inputs: (
    (
      name: "Bettor set",
      wallet: true,
      address: "bettor_addr",
      value: ("YES_market_id": "m", "NO_market_id": "n", "MarketFeeAsset": "m"),
    ),
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [ClaimDraw],
    ),
    (
      reference: true,
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [*Draw*],
        collateral: "TokenInfo",
        resolution_timeout: "PosixTime",
        claim_timeout: "PosixTime",
        "...": [],
      ),
    ),
  ),
  mint: (
    "YES_market_id": "-m",
    "NO_market_id": "-n",
  ),
  validRange: (upper: "claim_timeout"),
  outputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N - (m + n) / 2", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
    ),
    (
      name: "Bettor refund",
      wallet: true,
      address: "bettor_addr",
      value: ("Collateral": "(m + n) / 2"),
    ),
  ),
)

#figure(refund_tx, caption: [Refund on Draw transaction]) <fig:refund>

#pagebreak()

= Refund on None (Claim Timeout)
_When the market still has `None` as winner after `resolution_timeout` (and before `claim_timeout`), every participant refunds by burning any amount of YES/NO tokens for half collateral each._

#let refund_tx = vanilla_transaction(
  "Refund None (Claim Timeout)",
  inputs: (
    (
      name: "Bettor set",
      wallet: true,
      address: "bettor_addr",
      value: ("YES_market_id": "m", "NO_market_id": "n", "MarketFeeAsset": "m"),
    ),
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [ClaimTimeout],
    ),
    (
      reference: true,
      name: "Outcome",
      address: "outcome_script",
      value: ("Beacon": "1"),
      datum: (
        market_id: "ByteArray",
        winner: [_None_],
        collateral: "TokenInfo",
        resolution_timeout: "PosixTime",
        claim_timeout: "PosixTime",
        "...": [],
      ),
    ),
  ),
  mint: (
    "YES_market_id": "-m",
    "NO_market_id": "-n",
  ),
  validRange: (upper: "claim_t", lower: "resolution_t"),
  outputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "N - (m + n) / 2", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
    ),
    (
      name: "Bettor refund",
      wallet: true,
      address: "bettor_addr",
      value: ("Collateral": "(m + n) / 2"),
    ),
  ),
)

#figure(refund_tx, caption: [Refund on None transaction]) <fig:refund>

#pagebreak()

= Sweep Residual
_After the claim timeout, all accumulated fees and any residual collateral can be swept by the market address._

#let sweep_tx = vanilla_transaction(
  "Sweep Residual",
  inputs: (
    (
      name: "Redemption",
      address: "redemption_script",
      value: ("Collateral": "k", "MarketFeeAsset": "m"),
      datum: (
        market_id: "ByteArray",
        beacon_policy: "PolicyId",
      ),
      redeemer: [SweepResidual]
    ),
  ),
  validRange: (lower: "claim_timeout"),
  outputs: (
    (
      name: "Market payout",
      wallet: true,
      address: "market_addr",
      value: ("Collateral": "k", "MarketFeeAsset": "m"),
    ),
  ),
)

#figure(sweep_tx, caption: [Sweep residual transaction]) <fig:sweep>

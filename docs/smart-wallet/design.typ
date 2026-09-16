// Smart Wallet with Pluggable Authorization Credential — transaction design.
// Implements issue #11 (contracts-library): L1 forwarding credential + L2
// self-governing config + two worked L3 scripts (fixed-action mandate,
// bounded allowance). Positions taken (rationale in the notes):
//   - the treasury spend script forwards unconditionally (its only rule is
//     that the wallet credential ran); the credential's redeemer dispatches
//     all authorization modes — Approve (M-of-N), Override (supervisor),
//     Mandate (one-shot execution)
//   - witness-model approvals: M-of-N signatures against the config UTxO,
//     aggregated off-chain; supervisor override for owner supremacy
//   - config epoch bump = bulk invalidation of outstanding mandates/grants
//   - mandates are one-shot UTxOs, burned at execute — bounded loss
//   - allowances are value-bounded pots: the ledger enforces the cap, nothing
//     is counted
// The spec and exploration documents follow separately.

#import "../diagrams-template.typ": *

#show: report

= Deploy wallet (config genesis)
_Mints the one-shot `Config NFT` from the parameterized seed UTxO and locks the
initial configuration: members, threshold, policy and supervisor._

#let deploy_tx = vanilla_transaction(
  "Deploy wallet",
  inputs: (
    (
      name: "Seed UTxO",
      value: ("ada": "1"),
    ),
    (
      name: "Deployer fee",
      wallet: true,
      value: ("ada": "fees"),
    ),
  ),
  mint: (
    "Config NFT": 1,
  ),
  outputs: (
    (
      name: "Config UTxO",
      address: "config_addr",
      value: (
        "Config NFT": "1",
        "ada": "min_ada",
      ),
      datum: (
        members: "List(Credential)",
        threshold: "Int",
        supervisor: "Credential",
        policy: "List(ScriptHash)",
        epoch: 0,
      ),
    ),
  ),
  signatures: (
    "seed holder (deployer)",
  ),
  notes: [
    - `config_addr`: payment is `config_hash`, staking any.
    - `config_hash = hash(config_validator(seed_utxo, config_token_name, credential_hash))`
    - `credential_hash = hash(credential_validator(config_policy, mandate_policy))`:
      the wallet credential is a withdraw-0 *staking* script — the pluggable
      `Credential` consumers embed wherever a signer is expected. Its redeemer
      dispatches the authorization modes (`Approve`, `Override`, `Mandate`).
      It runs at most once per transaction (one withdrawal per address), and
      any number of contracts can observe it, asserting only that it ran.
    - `wallet_hash = hash(spend_validator(credential_hash))`: the treasury's
      only parameter is the credential; `mandate_hash` and `pot_hash` follow
      from the same constants, so all five scripts deploy together.
    - the treasury is itself a consumer: it asserts only that the credential
      ran — all authorization logic lives behind the credential.
    - the mint requires spending `seed_utxo`: a UTxO can be spent only once, so
      the Config NFT is one-shot and at most one config can ever exist (burn to
      close, never re-mint).
    - `members`: the n signers of the M-of-N floor; `threshold`: the minimum m;
      `policy`: extra withdrawal scripts that must also run on every approved
      spend; `supervisor`: a cold credential with override power.
  ],
)

#figure(deploy_tx, caption: [Deploy wallet (config genesis)]) <fig:deploy>

#pagebreak()

= Plain spend (M-of-N floor)
_The treasury pays out under the group's own quorum: the spend script only
forwards to the wallet credential, which checks M-of-N against the config._

#let plain_spend_tx = vanilla_transaction(
  "Plain spend",
  inputs: (
    (
      name: "Treasury UTxO",
      address: "wallet_addr",
      redeemer: [Spend],
      value: ("ada": "x"),
    ),
    (
      reference: true,
      name: "Config UTxO",
      address: "config_addr",
      value: ("Config NFT": "1"),
      datum: (
        members: "",
        threshold: "",
        supervisor: "",
        policy: "",
        epoch: "",
      ),
    ),
  ),
  withdrawals: (
    "wallet_credential: Approve",
  ),
  outputs: (
    (
      name: "Payout",
      wallet: true,
      value: ("ada": "y"),
    ),
    (
      name: "Treasury change (if partial)",
      address: "wallet_addr",
      value: ("ada": "x - y"),
    ),
  ),
  signatures: (
    "any m of the n members (extra_signatories)",
  ),
  notes: [
    - `wallet_addr`: payment is `wallet_hash`; treasury UTxOs carry no datum.
      They may hold ada and arbitrary native assets.
    - `wallet_hash = hash(spend_validator(credential_hash))`: the spend script
      is an unconditional forwarder — its only rule is that a withdrawal from
      the wallet credential is present. The redeemer carries no mode.
    - the credential's `Approve` mode does the work: it requires the config
      UTxO as a reference input, reads `members`/`threshold` from it, and
      requires at least `threshold` of `members` in `extra_signatories`
      (witness model: signatures aggregated off-chain, no on-chain proposal).
    - every script hash in config `policy` must also withdraw (conjunction):
      the required constraint set travels in the config, so a spend cannot
      satisfy the credential while omitting a required constraint script.
    - supervisor variant (owner supremacy): redeemer `Override` on the
      credential, supervisor signature, no config reference anywhere — works
      even when the config is malformed or stale.
    - no validity-range constraint on approval; constraint scripts in
      `policy` may add their own bounds.
  ],
)

#figure(plain_spend_tx, caption: [Plain spend (M-of-N floor)]) <fig:plain-spend>

#pagebreak()

= Update config (self-governance)
_The group updates its own membership, threshold, policy or supervisor without
redeploying any consumer; the update bumps the epoch._

#let update_config_tx = vanilla_transaction(
  "Update config",
  inputs: (
    (
      name: "Config UTxO",
      address: "config_addr",
      redeemer: [Update],
      value: (
        "Config NFT": "1",
        "ada": "min_ada",
      ),
      datum: (
        members: "",
        threshold: "",
        supervisor: "",
        policy: "",
        epoch: [*e*],
      ),
    ),
  ),
  withdrawals: (
    "wallet_credential: Approve (or supervisor: Override)",
  ),
  outputs: (
    (
      name: "Config UTxO",
      address: "config_addr",
      value: (
        "Config NFT": "1",
        "ada": "min_ada",
      ),
      datum: (
        members: [*members'*],
        threshold: [*m'*],
        supervisor: [*supervisor'*],
        policy: [*policy'*],
        epoch: [*e + 1*],
      ),
    ),
  ),
  signatures: (
    "any m of the n members (or the supervisor)",
  ),
  notes: [
    - transition checks (config script): `1 <= threshold <= len(members)`;
      `policy` entries are withdrawal script hashes; all credentials
      well-formed. An update that could brick the wallet is rejected.
    - the epoch bump is bulk invalidation (Squads-style): every outstanding
      mandate and allowance grant records the config epoch it was created
      under; a bumped epoch makes them all stale in one write — no per-item
      cancellation after a key rotation.
    - the supervisor signature alone authorizes the update too (owner
      supremacy; the credential's `Override` path).
  ],
)

#figure(update_config_tx, caption: [Update config (self-governance)]) <fig:update-config>

#pagebreak()

= Create mandate (fixed-action grant)
_A quorum (or the supervisor) pre-commits one exact action: recipient, asset
bundle, expiry. The mandate UTxO is the authorization token; it is consumed at
execute, so a mandate is one-shot by construction._

#let create_mandate_tx = vanilla_transaction(
  "Create mandate",
  inputs: (
    (
      name: "Fee payer",
      wallet: true,
      value: ("ada": "fees"),
    ),
  ),
  mint: (
    "Mandate NFT": 1,
  ),
  withdrawals: (
    "wallet_credential: Approve (or supervisor: Override)",
  ),
  outputs: (
    (
      name: "Mandate UTxO",
      address: "mandate_addr",
      value: (
        "Mandate NFT": "1",
        "ada": "min_ada",
      ),
      datum: (
        action: (
          recipient: "Address",
          assets: "Value",
        ),
        expiry: "PosixTime",
        epoch: [*config.epoch*],
      ),
    ),
  ),
  signatures: (
    "any m of the n members (or the supervisor)",
  ),
  notes: [
    - `mandate_addr`: payment is `mandate_hash`.
    - `mandate_hash = hash(mandate_validator(credential_hash, wallet_policy, config_policy))`
    - the mint endpoint requires the wallet credential (M-of-N) or the
      supervisor signature, and fully checks the mandate output (one NFT,
      well-formed datum).
    - `epoch` records the config epoch at creation: the mandate is valid only
      while the config epoch is unchanged (key rotation invalidates it).
    - `expiry` bounds the mandate's life; `Cancel` (quorum or supervisor, burn)
      revokes it earlier and `Reap` (anyone, after expiry, burn) reclaims the
      deposit — no liveness lock from stale mandates.
    - nested authority: a member may itself be a script, so the granting
      quorum can be another multisig, a DAO, an oracle attestation, …
  ],
)

#figure(create_mandate_tx, caption: [Create mandate (fixed-action grant)]) <fig:create-mandate>

#pagebreak()

= Execute mandate (one-shot spend)
_Anyone can execute a live mandate: the treasury pays exactly the mandated
action. No live quorum is needed at execution time — the grant carried the
authority, and one-shot consumption rules out double execution._

#let execute_mandate_tx = vanilla_transaction(
  "Execute mandate",
  inputs: (
    (
      name: "Treasury UTxO",
      address: "wallet_addr",
      redeemer: [Spend],
      value: ("ada": "x"),
    ),
    (
      name: "Mandate UTxO",
      address: "mandate_addr",
      redeemer: [Execute],
      value: (
        "Mandate NFT": "1",
        "ada": "min_ada",
      ),
      datum: (
        action: (
          recipient: "",
          assets: "",
        ),
        expiry: "",
        epoch: "",
      ),
    ),
    (
      reference: true,
      name: "Config UTxO",
      address: "config_addr",
      value: ("Config NFT": "1"),
      datum: (
        epoch: "",
        "...": [],
      ),
    ),
  ),
  mint: (
    "Mandate NFT": -1,
  ),
  withdrawals: (
    "wallet_credential: Mandate",
  ),
  outputs: (
    (
      name: "Mandated payout",
      wallet: true,
      value: (
        "ada": "y",
        "asset": "q",
      ),
    ),
    (
      name: "Treasury change",
      address: "wallet_addr",
      value: ("ada": "x - y"),
    ),
  ),
  validRange: (lower: "now", upper: "expiry"),
  notes: [
    - no signatures: the mandate is the live authority (delegation without
      co-located signers).
    - treasury script: an unconditional forwarder, exactly as on a plain
      spend — the only difference is the credential's redeemer.
    - credential (`Mandate` mode): the tx consumes a mandate UTxO under
      `mandate_policy` whose NFT is burned here, and the config reference must
      show `epoch == mandate.epoch` (stale mandates die at rotation). No
      M-of-N is required at execution time.
    - mandate script (`Execute`): the NFT burn is exact, the tx spends the
      treasury, and the payout output carries at most the mandated bundle to
      the mandated recipient — equality-or-less keeps composability (other
      outputs are ignored).
    - interval-bound discipline: the upper bound makes the validity range
      entirely before `expiry`; the lower bound must be finite — a tx with an
      unbounded range proves nothing about when it executes.
    - `Cancel` (quorum or supervisor, burn) and `Reap` (anyone, after expiry,
      burn) share this shape with different authorization and timing.
  ],
)

#figure(execute_mandate_tx, caption: [Execute mandate (one-shot spend)]) <fig:execute-mandate>

#pagebreak()

= Refill allowance pot
_A quorum refills the period budget: the pot is topped up to at most
`allowance`, and the unspent prior allowance is swept back. The cap is the
pot's value — the ledger enforces it, nothing is counted._

#let refill_pot_tx = vanilla_transaction(
  "Refill pot",
  inputs: (
    (
      name: "Treasury UTxO",
      address: "wallet_addr",
      redeemer: [Spend],
      value: ("ada": "x"),
    ),
    (
      name: "Pot UTxO",
      address: "pot_addr",
      redeemer: [Refill { grant }],
      value: (
        "Pot NFT": "1",
        "ada": "r",
      ),
      datum: (
        delegatee: "",
        allowance: "",
        period_start: "",
        period_end: "",
        epoch: "",
      ),
    ),
  ),
  withdrawals: (
    "wallet_credential: Approve",
  ),
  outputs: (
    (
      name: "Pot UTxO",
      address: "pot_addr",
      value: (
        "Pot NFT": "1",
        "ada": "≤ a",
      ),
      datum: (
        delegatee: [*delegatee'*],
        allowance: [*a*],
        period_start: [*now*],
        period_end: [*now + period*],
        epoch: [*config.epoch*],
      ),
    ),
    (
      name: "Treasury change",
      address: "wallet_addr",
      value: ("ada": "x + r - a"),
    ),
  ),
  validRange: (lower: "period_start"),
  signatures: (
    "any m of the n members (or the supervisor)",
  ),
  notes: [
    - `pot_addr`: payment is `pot_hash`.
    - `pot_hash = hash(pot_validator(credential_hash, wallet_policy, config_policy))`
    - the first refill for a delegatee also mints the `Pot NFT` (+1) and may
      omit the pot input; the allowance may be ada and/or native tokens.
    - the unspent prior allowance `r` is swept back to the treasury, so the
      pot never exceeds the new allowance: the pot's value *is* the budget.
    - rollover gating: the pot script requires a finite lower bound with
      `now >= period_end` of the spent pot, so a period's budget can be topped
      at most once — contention once per period, not once per spend.
    - the grant (delegatee, allowance, period) is written by the refill, which
      is quorum-authorized via the credential's `Approve` path; `epoch` records
      the config epoch, so a rotation revokes the standing grant (re-grant by
      refilling). `Reclaim` (quorum or supervisor, burn) returns the pot's
      contents to the treasury at any time — immediate revocation.
  ],
)

#figure(refill_pot_tx, caption: [Refill allowance pot]) <fig:refill-pot>

#pagebreak()

= Delegatee spend (from pot)
_The delegatee spends the pot's contents at discretion: no quorum, no config
read, no treasury involvement. The period's loss bound is exactly the pot's
value._

#let delegatee_spend_tx = vanilla_transaction(
  "Delegatee spend",
  inputs: (
    (
      name: "Pot UTxO",
      address: "pot_addr",
      redeemer: [DelegateeSpend],
      value: (
        "Pot NFT": "1",
        "ada": "v",
      ),
      datum: (
        delegatee: "",
        allowance: "",
        period_start: "",
        period_end: "",
        epoch: "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Delegatee payout",
      wallet: true,
      value: ("ada": "y"),
    ),
    (
      name: "Pot change (if partial)",
      address: "pot_addr",
      value: (
        "Pot NFT": "1",
        "ada": "v - y",
      ),
      datum: (
        delegatee: "",
        allowance: "",
        period_start: "",
        period_end: "",
        epoch: "",
      ),
    ),
  ),
  signatures: (
    "delegatee (or the delegatee credential runs — recursion)",
  ),
  notes: [
    - deliberately cheap: no config reference, no quorum, no treasury input —
      the delegatee lane never contends with the members' lane, and multiple
      pots (sharded budgets) run in parallel.
    - the pot script checks only the delegatee authorization (signature, or a
      withdrawal if the delegatee is itself a script credential) and, for the
      continuation, exact address + NFT + datum reproduction.
    - no epoch check on delegatee spends: the lane stays config-free. A
      rotation revokes via `Reclaim` (immediate) and the next refill refuses
      the stale grant.
    - the cap needs no counter: the pot's value is the spendable budget, and
      only refills can raise it. A fully compromised delegatee loses at most
      the pot.
    - failures are correlated across a fleet running the same model:
      per-credential pots bound the loss per credential, not the aggregate —
      shard or fleet-level budgets for fleets sharing one authority.
  ],
)

#figure(delegatee_spend_tx, caption: [Delegatee spend (from pot)]) <fig:delegatee-spend>

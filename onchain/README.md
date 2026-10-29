# On-chain

The Aiken workspace for ContractsLibrary: the validation logic the Cardano ledger enforces. This is the only layer that carries security. The off-chain builders, specs, and proofs all describe or exercise what lives here.

For the project as a whole (off-chain, specs, formal proofs, contributor docs), see the [repository README](../README.md).

## Layout

```
lib/<contract>/   reusable, parameterized validation predicates (the real logic)
lib/*.ak          shared cross-contract helpers (e.g. authorization.ak)
validators/       thin reference validators that dispatch a redeemer to lib/
artifacts/        committed UPLC for inspection / formal verification
plutus.json       generated blueprint (compiled code + datum/redeemer schemas)
```

Each contract is split into two parts on purpose:

- **`lib/<contract>/`** holds well-behaved predicates that avoid global assumptions about transaction shape, so contracts compose freely in shared transactions. This is what you import to compose or fork.
- **`validators/<contract>.ak`** (or `validators/<contract>/` for contracts with several validators, e.g. settings and smart wallet) is a thin wrapper that decodes the redeemer and delegates to `lib/`. Use it as-is, or embed the `lib/` functions in your own validator.

See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for the composability conventions every contract follows.

## Where each contract is explained

A validator here is an *implementation*. The authoritative description of what each contract does (its state, actions, and invariants) lives outside this workspace:

- **Specs**: Implementation-independent behavior, the source of truth: [`docs/<contract>/spec.md`](../docs/).
- **Formal proofs**: Machine-checked Lean 4 proofs of those specs (completeness, soundness, robustness): [`../formal/`](../formal/).

When reading a validator, start from its spec; the code comments reference spec sections (e.g. `§5.2`) rather than restating them.

## Contracts


| Contract | Library | Validator | Spec |
|---|---|---|---|
| Linear vesting | `lib/vesting/` | `validators/linear_vesting.ak` | [`../docs/vesting/spec.md`](../docs/vesting/spec.md) |
| DAO | `lib/dao/` | `validators/dao/{proposal,stake,vote}.ak` (+ `poll_effect.ak`) | [`../docs/dao/spec.md`](../docs/dao/spec.md) |
| Settings | `lib/settings/` | `validators/settings/{settings,settings_typed}.ak` | [`../docs/settings/spec.md`](../docs/settings/spec.md) |
| Smart wallet | `lib/smart_wallet/` | `validators/smart_wallet/smart_wallet.ak` (+ `withdrawal_scripts/`) | [`../docs/smart-wallet/spec.md`](../docs/smart-wallet/spec.md) |
| Event-triggered assets | `lib/event_triggered/` | `validators/event_triggered_assets.ak` | [`../docs/event-triggered-assets/spec.md`](../docs/event-triggered-assets/spec.md) |


More contracts (escrow, AMM, CIP-68, …) are triaged in the [PRD](../docs/PRD.md#7-contract-catalog).

## Building and testing

```sh
aiken build          # compile validators, regenerate plutus.json
aiken check          # run all tests (unit + property/fuzz)
aiken check -m foo   # run only tests matching "foo"
aiken docs           # generate HTML API docs for the lib modules
```

Tests live alongside the code they cover in `*.test.ak` files. Property tests use [`aiken-lang/fuzz`](https://github.com/aiken-lang/fuzz).

### Property-based tests

Default to property-based tests wherever a law or invariant can be expressed;
keep unit tests for exact boundaries, regression pins, and rule-specific
`must-reject` cases.

- Use `aiken/fuzz` and `cardano/fuzz` (addresses, credentials, values, inputs,
  outputs, datums, certificates, withdrawals). Aiken shrinks counterexamples
  automatically: do not write custom generators or shrinkers — compose fuzzers
  with `map`, `and_then`, `tuple`, `either`, `such_that` and the existing
  fixtures.
- Name properties `prop_*` and use `fuzz.label*` for interesting branches
  (empty vs non-empty, key vs script, boundaries).
- `aiken check` runs property tests with 100 samples by default. Reproduce a
  failure with the seed it reports: `aiken check --seed <seed>`.
- CI runs the PR suite at `--max-success=100`; the nightly job runs
  `--max-success=1000`.

## Resources

- [Aiken user manual](https://aiken-lang.org)
- [Aiken standard library](https://aiken-lang.github.io/stdlib/)

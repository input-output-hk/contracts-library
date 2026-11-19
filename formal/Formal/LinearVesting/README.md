# vesting/linear — formal proofs

Lean model lemmas and compiled-validator proof targets for **linear vesting**.
See the spec [`spec.md`](../../../docs/vesting/spec.md)
(the source of truth, with §8 completeness / §9 soundness clauses) and the
on-chain types [`types.ak`](../../../onchain/lib/vesting/types.ak). For the
toolchain, build, and general `blaster` notes, see the
[`formal/` README](../../README.md).

For the milestone 1.2 review scope and checklist, see
[issue #12](https://github.com/no-witness-labs/contracts-library/issues/12).

[`properties.json`](properties.json) indexes the 31 theorem declarations in
`Spec`, `Completeness`, `Soundness`, and `Robustness` across 21 entries.

## Validator snapshot

[`validator-metadata.json`](validator-metadata.json) records the upstream source
snapshot. The CBOR and compiler details come from `onchain/plutus.json` at the
recorded commit. The source in PR #16 has one extra trailing newline. With
Aiken `v1.1.22+39d6b04`, it produces the recorded vesting bytecode. The decoded
CBOR payload matches the Flat artifact loaded by `Script.lean`.

## Modules

- `Spec.lean` — the pure model (`vested`/`required`, datum/redeemer encoding,
  shared datum fixtures); no UPLC.
- `Script.lean` — loads the compiled `spend` validator (`spendValidator`).
- `Completeness.lean` — `spec ⇒ accepts` (§8).
- `Soundness.lean` — `accepts ⇒ spec` (§9), plus the shared context builders.
- `Robustness.lean` — rejection theorems (§9 R-clauses, §5.1).
- `SpecNew.lean` defines `specAccepts` for Claim and Cancel and proves six arithmetic lemmas.
- `Cancel.lean` states agreement with the compiled validator for a constructed
  cancel transaction. The theorem assumes at most two signatories for a key
  locker or at most two withdrawals for a script locker.
- `Claim.lean` states agreement for a constructed single-input claim with a key
  beneficiary, one vested asset, a positive-infinite upper time bound, at most
  one signatory, and at most two outputs.
- `Corollaries.lean` derives nine soundness and completeness results within
  the scope of those agreement theorems.

## Standard instance

Where a theorem fixes values, the standard instance is: schedule
`start/end/recovery = 1000/2000/3000`, asset total 100, `now` in the open window
`(1000, 2000)`, beneficiary/locker as key credentials. The tables and each
theorem's hypotheses describe the covered cases.

### Spec arithmetic (`Spec.lean`, no UPLC)

| Theorem | Spec clause |
|---|---|
| `vested_preStart` | B3 (nothing vests before `start`) |
| `vested_full` | I4 (all vested at/after `end`) |
| `vested_le_total` | Total cap (`vested ≤ total`), not B1's floor bound |
| `vested_nonneg`, `required_nonneg` | `vested ∈ [0, total]` |
| `vested_mono` | B2 (`vested` non-decreasing in `now`) |

### Completeness — `spec ⇒ accepts` (§8)

| Theorem | Spec clause |
|---|---|
| `claim_complete_partial` | `C0–C4, I3` (constructed single-native-asset claim, valid schedule, `now < end`, matching payment credential) |
| `claim_accept_generic_schedule` | C0–C4, I3 (general single-asset partial claim: symbolic identities, total, **schedule**, `now`, amount) |
| `claim_accept_anytime` | C0–C4 across all `now`, symbolic ada (full-retention) |
| `claim_complete_full` | §8.2, I4 (full claim once `now ≥ end`) |
| `claim_accept_script_auth` | C1 (script beneficiary via withdraw-0) |
| `claim_accept_two_inputs` | §5.1, C4 (two separately funded continuations accepted) |
| `cancel_complete` | C6–C8 (authorized cancel after recovery) |

### Robustness — rejection (§9 R-clauses, §5.1)

| Theorem | Spec clause |
|---|---|
| `reject_unauthorized_claim`, `reject_unauthorized_claim_no_sig`, `reject_wrong_signer` | R1 (unauthorized claim) |
| `reject_over_release`, `reject_over_release_concrete` | R2 (over-release) |
| `reject_datum_tamper`, `reject_datum_tamper_concrete` | R3 (schedule/datum tampering) |
| `reject_datum_hash_input` | R4 (datum-hash input) |
| `reject_premature_cancel` | R6 (cancel before recovery, strict) |
| `reject_unauthorized_cancel` | I5 (unauthorized cancel) |
| `reject_script_no_withdrawal` | R1 (script beneficiary, no withdrawal) |
| `no_double_satisfaction` | §5.1, I2 (one continuation cannot satisfy two inputs) |
| `reject_merged_instances` | §5.1, C4 (one combined continuation rejected despite sufficient aggregate value) |
| `reject_underfunded_batch` | §5.1, C4 (each continuation must hold its own required remainder) |

### Soundness — `accepts ⇒ spec` (§9)

| Theorem | Spec clause |
|---|---|
| `claim_sound_partial`, `claim_sound_partial_concrete` | I2 + I3 (acceptance forces datum reproduction and `≥ required`) |
| `cancel_sound` | I5 / C7 (acceptance forces `now > recovery_time`) |

## Proof status

All five general targets tracked in [issue #17](https://github.com/no-witness-labs/contracts-library/issues/17) have proofs.
The catalogue's theorem references have no `sorryAx` dependencies; they retain
Blaster's SMT trust axiom.

`claim_sound_partial` derives datum reproduction from acceptance; it does not
assume the output datum matches.

## Remaining work

- **Multi-asset bundles** (`vesting` of length > 1): structural/unbounded, so
  likely only feasible at fixed small lengths.

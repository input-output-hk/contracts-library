# vesting/linear — formal proofs

Machine-checked proofs for the **linear vesting** contract, against the compiled
validator. See the spec [`linear-vesting.md`](../../../../specs/vesting/linear-vesting.md)
(the source of truth, with §8 completeness / §9 soundness clauses) and the
on-chain types [`types.ak`](../../../../onchain/lib/vesting/types.ak). For the
toolchain, build, and general `blaster` notes, see the
[`formal/` README](../../../README.md).

## Modules

- `Spec.lean` — the pure model (`vested`/`required`, datum/redeemer encoding,
  shared datum fixtures); no UPLC.
- `Script.lean` — loads the compiled `spend` validator (`spendValidator`).
- `Completeness.lean` — `spec ⇒ accepts` (§8).
- `Soundness.lean` — `accepts ⇒ spec` (§9), plus the shared context builders.
- `Robustness.lean` — rejection theorems (§9 R-clauses, §5.1).

## Standard instance

Where a theorem fixes values, the standard instance is: schedule
`start/end/recovery = 1000/2000/3000`, asset total 100, `now` in the open window
`(1000, 2000)`, beneficiary/locker as key credentials. The encodings mirror
`types.ak` and `cardano/address` exactly. Coverage for this single-asset
instance is comprehensive across all three directions.

### Spec arithmetic (`Spec.lean`, no UPLC)

| Theorem | Spec clause |
|---|---|
| `vested_preStart` | B3 (nothing vests before `start`) |
| `vested_full` | I4 (all vested at/after `end`) |
| `vested_le_total` | B1 (no over-release) |
| `vested_nonneg`, `required_nonneg` | `vested ∈ [0, total]` |
| `vested_mono` | B2 (`vested` non-decreasing in `now`) |

### Completeness — `spec ⇒ accepts` (§8)

| Theorem | Spec clause |
|---|---|
| `claim_accept_generic_schedule` | C0–C4, I3 (general single-asset partial claim: symbolic identities, total, **schedule**, `now`, amount) |
| `claim_accept_anytime` | C0–C4 across all `now`, symbolic ada (full-retention) |
| `claim_complete_full` | §8.2, I4 (full claim once `now ≥ end`) |
| `claim_accept_script_auth` | C1 (script beneficiary via withdraw-0) |
| `claim_accept_two_inputs` | §5.1 (correctly funded batch accepted) |
| `cancel_complete` | C6–C8 (authorized cancel after recovery) |

### Robustness — rejection (§9 R-clauses, §5.1)

| Theorem | Spec clause |
|---|---|
| `reject_unauthorized_claim_no_sig`, `reject_wrong_signer` | R1 (unauthorized claim) |
| `reject_over_release_concrete` | R2 (over-release) |
| `reject_datum_tamper_concrete` | R3 (schedule/datum tampering) |
| `reject_datum_hash_input` | R4 (datum-hash input) |
| `reject_premature_cancel` | R6 (cancel before recovery, strict) |
| `reject_unauthorized_cancel` | I5 (unauthorized cancel) |
| `reject_script_no_withdrawal` | R1 (script beneficiary, no withdrawal) |
| `no_double_satisfaction` | §5.1, I2 (`k`-scaling: one continuation cannot satisfy two inputs) |

### Soundness — `accepts ⇒ spec` (§9)

| Theorem | Spec clause |
|---|---|
| `claim_sound_partial_concrete` | I2 + I3 (acceptance forces datum reproduction and `≥ required`) |
| `cancel_sound` | I5 / C7 (acceptance forces `now > recovery_time`) |

## Not proved (documented `∀`-targets, left as `sorry`)

These surface as build warnings (`warn.sorry` is enabled). Each is the fully
`∀`-quantified version of a proved concrete theorem
(`claim_complete_partial`, `claim_sound_partial`, `reject_unauthorized_claim`,
`reject_over_release`, `reject_datum_tamper`), kept to document the intended
general statement.

**Why they are not proved:** the `∀` over an unconstrained
datum/schedule/amounts/addresses makes `blaster` symbolically execute the CEK
machine over an unbounded `ScriptContext`, which does not terminate. The concrete
instances discharge the same properties for the standard instance; the spec's
§8/§9 carry the general statements in prose.

The continuation datum is kept **arbitrary** in the soundness and robustness
theorems, so the proofs *derive* datum-reproduction rather than assume it.

## Remaining work

- **Multi-asset bundles** (`vesting` of length > 1): structural/unbounded, so
  likely only feasible at fixed small lengths.
- **Unified `∀` statements**: the `sorry` targets above; would need a proof
  strategy beyond direct symbolic execution (e.g. lemmas about the validator's
  structure).

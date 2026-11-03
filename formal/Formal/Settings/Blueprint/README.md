# UP-016: mint quantity

Standalone candidate for [issue #37](https://github.com/no-witness-labs/contracts-library/issues/37)
and [draft PR #64](https://github.com/no-witness-labs/contracts-library/pull/64).
The original rejection and applicability propositions remain unchanged.
Separate proof invocations and a synthetic accepting control are in
[`tests/UP016`](../../../tests/UP016/).

UP-016 is an **incomplete proof checkpoint**. On 2026-11-03, the owner approved
consolidating the retained implementation while carrying unfinished proofs to
fresh branches. This exception does not complete checkpoint 1's proof work.
The symbolic files are opt-in: `Formal.lean` does not import them, and the
default build does not execute these checks.

The Settings Mint example has one seed input and two outputs. The mutation
increases the existing token quantity from `1` to `1 + delta` and credits
`delta` to output 1. Output 0 stays unchanged. The claim requires positive
`delta`, an accepted original context, and model validity for both contexts.
Rejection means an error or a non-unit halt within **1,000,000 CEK steps**;
exhaustion does not count. This step bound is not a ledger CPU or memory budget.

`MintLeaves` leaves ADA amounts, fee, time, and the integer-valued current
datum symbolic. The claim adds no upper bound on those integers or `delta`.
The fixed parameter instance and transaction structure restrict its coverage.
Model validity means `validScriptContext` in the pinned ledger library; it
does not establish transaction reachability on a deployed ledger.

## Retained artifact and parameters

[Validator metadata](validator-metadata.json) records the exact upstream source,
raw `.ak` file hash, applied CBOR, compiler, and serialized parameters. Source:
[IO commit `96c9f32`](https://github.com/input-output-hk/contracts-library/commit/96c9f328060b1664402134d71fdf0bc4a838fba7),
[`settings.ak`](https://github.com/input-output-hk/contracts-library/blob/96c9f328060b1664402134d71fdf0bc4a838fba7/onchain/validators/settings.ak),
and [`settings/mint.ak`](https://github.com/input-output-hk/contracts-library/blob/96c9f328060b1664402134d71fdf0bc4a838fba7/onchain/lib/settings/mint.ak).
The source blueprint records Aiken `v1.1.22+39d6b04` and Apache-2.0 licensing.
These are synthetic test parameters, in application order:

| Parameter | Value |
| --- | --- |
| Seed reference | Transaction ID byte `11` repeated 32 times; index `0` |
| Proposer key | Byte `22` repeated 28 times |
| Apply key | Byte `33` repeated 28 times |
| Apply delay | `60000` ms |
| Token name | UTF-8 `UP016` |

Byte values above are hexadecimal. Applied Plutus V3 policy hash:
`50dc52e6bf8db417d8e5b70bbd2c1caa6a45a5ca7854a51d99b63e60`.
The applied single-CBOR artifact has 2,679 bytes and SHA-256:
`527f551e2b615d50ce44679e9bc585552cac8c549a0637864eb93e4c34f2ec50`.
The unparameterized blueprint artifact has 2,544 bytes and SHA-256:
`d3cdb83bc4248cb59f2681e47c46aeb7f0da2be0621f80f6adb2d4e1e566250f`.
The raw validator source has SHA-256:
`aa99e9118721bdfe26fd6abe059cfd1a1f8b32d2b5a3634168aeb86ed246cc75`.

`Types.lean` embeds the exact recorded applied artifact through the same Lean
decoder used by the former ignored-file import. Preparation needs no generated
CBOR file, Python, or Aiken recompilation. It does not reapply parameters.
`VerifyArtifact.lean` checks the source digest, compiler metadata, artifact
digests, actual V3 policy hash, proof program, and fixed parameter values. It
also checks that the applied syntax tree is exactly the tracked blueprint
program with those five `Data` arguments, in order. Both program and parameter
CBOR decoding require complete consumption. These checks establish retained
artifact consistency; they do not reproduce compilation from Aiken source.

## Standalone validation

Use Lean `v4.24.0`, Z3 `4.15.2`, and the dependency revisions recorded in
`lake-manifest.json`. The retained evidence below used these revisions:

| Dependency | Commit |
| --- | --- |
| Blaster | `402f6d22c1fc42e6e26255faac77e15b2450e4ab` |
| PlutusCore | `4ef48606303c45225d3ed2e2a87fc50280a763b7` |
| CardanoLedgerApi | `577e3eb03b5be09354cfdb1c0d0c12e9e16541a0` |

From `formal/`, with the pinned dependencies available:

```sh
lake build Blaster Formal.Settings.Blueprint.MintQuantity
lake build up016_verify_artifact
timeout --kill-after=5s 60s .lake/build/bin/up016_verify_artifact
timeout --kill-after=5s 60s lake env lean --threads=4 --run tests/UP016/ConcreteControls.lean
```

The proof commands below are opt-in references, not a batch to run during
consolidation. Select the file or files and obtain a fresh execution budget
before a new proof attempt:

```sh
timeout --kill-after=5s 300s lake env lean --threads=4 tests/UP016/QuantityIncreaseRejects.lean
timeout --kill-after=5s 300s lake env lean --threads=4 tests/UP016/QuantityIncreaseApplies.lean
timeout --kill-after=5s 300s lake env lean --threads=4 tests/UP016/AcceptingControl.lean
```

Run selected proof files sequentially within the agreed total deadline and
memory limit. A shared deadline must cover the whole selected sequence; the
individual command limits above do not grant a fresh budget to each file.
The files disable asynchronous elaboration and use four Lean workers.
A timeout is inconclusive; preserve its output without changing the domain,
fuel, or expected outcome. Do not retry it as part of the same run.

| Check | Expected observation |
| --- | --- |
| Artifact verifier | `UP016_ARTIFACT_AND_PARAMETERS_MATCH` |
| Original concrete runner | 17 `PASS` lines and `ALL_CONCRETE_CONTROLS_PASS 17` |
| Stronger rejection helper | `Valid`, followed by helper and derived-theorem axiom lists |
| Applicability theorem | `Valid`, followed by its axiom list |
| Synthetic accepting control | `Falsified` rejection, then `Valid` applicability |

The control substitutes a UPLC function that ignores its context and returns
unit, retaining both formulas, model, validity premises, and bound. It must
expose the missing rejection behavior while remaining applicable. Its context
retains the Settings policy identity: this is a synthetic harness control,
not another source-compiled or deployed minting policy. Expected falsification
uses `solve-result: 1`, so the expected process exit is `0` after both expected
observations. Import failures, timeouts, and unrelated errors do not count as
the expected observation.

The support modules build. Native artifact verification passed the source,
SHA-256, policy-hash, and five-parameter syntax-tree checks. All 17 original
concrete controls passed. The earlier interpreted artifact command
(`lake env lean --run tests/UP016/VerifyArtifact.lean`) reached its 60-second
deadline; the native executable above provides the completed verification.

The first direct rejection proof reached its 300-second deadline without a
solver observation. That result remains inconclusive. A proof-only adjustment
asks Blaster to prove the stronger helper
`∀ p delta, delta > 0 → rejects ledgerFuel (changed p delta)`, then derives the
unchanged original proposition by supplying only the positive-delta premise.
The helper omits assumptions from its own obligation; it does not weaken the
original property or replace explicit rejection with non-acceptance.

On 2026-11-03, definition/support compilation passed again, and one separately
authorized attempt ran the stronger helper. It timed out after **300.006
seconds** (exit `124`) without a solver verdict. The original-statement
derivation, applicability proof, and synthetic accepting control did not run.
The empty default-verbosity log does not identify the stalled phase or show
whether the solver started. These symbolic checks remain incomplete; the
earlier artifact and concrete-control successes do not discharge them. No
further proof attempt is part of this consolidation.

Definitions and runners alone are not proof results. This candidate adds no
axiom or admitted proof. The pinned PlutusCore build reports an existing `sorry`
warning in `CekMachine`;
record successful theorem axiom output and retain Blaster's SMT trust boundary.

## Attribution and checkpoint 2

Types and evaluator predicates originate in the existing blueprint generator
at [`6c2bd75`](https://github.com/no-witness-labs/contracts-library/blob/6c2bd759e7fb1332991210f88fcf748ec2d4e72c/formal/scripts/process_blueprint.py).
Shared source was extracted from
[PR #44 at `99a5734`](https://github.com/no-witness-labs/contracts-library/pull/44).
The original Settings model, two propositions, and 17 controls come from
[PR #64 at `c2c0c53`](https://github.com/no-witness-labs/contracts-library/commit/c2c0c53885211ca816c8616efa577319cc70c34e).
This preparation change does not modify the generator, model, or propositions.

[Issue #37](https://github.com/no-witness-labs/contracts-library/issues/37)
remains the scope reference for deferred generic parameter preparation, wider
mint values and asset sets, more outputs, other datum forms, burns, new token
names, and additional validators. The unfinished rejection, applicability, and
synthetic-control checks also remain tracked there for work on fresh branches.
Native property/model registration is tracked in
[issue #89](https://github.com/no-witness-labs/contracts-library/issues/89), and
app integration in [issue #96](https://github.com/no-witness-labs/contracts-library/issues/96).
Registration and app integration remain checkpoint-2 work. This standalone
candidate does not claim that wider coverage or workflow integration is complete.

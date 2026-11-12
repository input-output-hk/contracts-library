# UP-007 native integration validation

UP-007 reports an official FAIL for the original vesting Claim fixture: the
staking-replacement rejection obligation is Falsified, and its applicability
obligation is Valid. The compiled stake-enforcing control reports a test-only
PASS with both obligations Valid. Both native obligations still expect Valid.

Implementation commit 7966b3e9d46a8dbc2355cf9efd7315e57128b8ed records the tested
source, based on foundation 781d92e. Validation ran on 2026-11-12 with
Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-007 property build and unit suite | Passed; 526 build jobs |
| Affected app/test build | Passed; 638 build jobs |
| Kernel equivalences | Original Claim statement and applicability preserved; mutation preserves all fields other than the selected staking credential |
| Native UP-007 app integration | One FAIL check; Falsified main and Valid applicability; 136.795 seconds |
| Unsupported vault | SKIPPED with unsupported reason; no execution or generated modules |
| Second vesting artifact | SKIPPED with property exclusion reason; no execution or generated modules |
| Compiled stake-enforcing control | PASS; two Valid observations; 21.388-second executor run |
| Qualification controls | Missing, inconclusive, or falsified applicability left either a Valid or Falsified main observation unresolved |
| Affected regressions | UP-014 and UP-011 property suites, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Separate public UP-007 CLI | One FAIL check; Falsified main and Valid applicability; 123.498-second app execution; exit 0 |

Both new suites and seven affected suites passed: nine targeted suites in total.
The aggregate registers 37 suites; this change did not run the full aggregate.
The separate public CLI command is:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-007 --timeout-ms 300000
```

Run it from the implementation checkout's `formal/` directory. A zero app exit
means orchestration and evidence retention completed. The individual property
still reports FAIL when its qualified observations falsify the rule.

## Evidence and control attribution

The original app run retained three generated Lean files, exact input and
property/model metadata, compiler logs, and shared-source snapshots. Its linked
obligations are `continuationStake_claim` and `continuationStake_claim_applies`.
The compiler's falsification exit does not hide the recorded counterexample or
the completed applicability result.

The enforcing control executes the existing frozen compiled stake-control
program. Preparation checks its blueprint, decoded program, compiler metadata,
and recomputed Plutus V3 script hash. Frozen source, manifest, lock, and blueprint
digests also matched. No Aiken rebuild occurred. The control checks the first
output's payment and staking credentials against the spent input, keeping the
native formulas, model, five guards, argument encoding, and CEK bound.

Control evidence uses a distinct test identity and null official property/model
binding metadata. Generated Types embeds the executed bytes and computed hash.
The control's `input.json` is its actual blueprint; `reference-input.json` is the
original vesting fixture, marked reference-only. Generated Tx and Checks retain
the native model and statements. The control adds no official catalogue entry.

Qualification controls use in-memory observations to check assessment policy.
They do not execute a solver or establish a validator property. Valid
applicability qualifies the main result; unavailable or unsuccessful supporting
evidence cannot qualify either a passing or failing verdict.

Initial workflow runs preceded the implementation commit and recorded dirty
base 781d92e. Their captured sources and 343-file runtime manifest match
7966b3e; the Git label alone does not identify those tested sources. Shared
helpers, generator, assessor, preparation, transaction models, dependency pins,
and historical standalone proof/control implementations are unchanged.

The public CLI ran from clean implementation commit 7966b3e. Its finished run
index contains no orchestration errors. Both obligations have complete evidence
and the exact applicability link. It retained three generated Lean files and
their compiler logs, exact input snapshots, and 18 compiled shared-source
snapshots. All source and compiled-file hashes match the saved index; source
hashes also match the working implementation.

The closure includes shared
Continuations without the UP-011/UP-014 properties or Cancel model. All 343
runtime source/configuration hashes still match. App timing excludes launcher
preparation.

## Interpretation

The kernel checks establish equivalence with the preserved scoped formulas.
Generated successful obligations retain Blaster's `blasterProven` SMT trust.
The build also retains the existing `PlutusCore.UPLC.CekMachine.lean:312`
`sorry` warning. This change neither introduces nor resolves that dependency gap.

The rule changes only the first continuation's optional staking credential.
It retains baseline validity and acceptance, explicit rejection after combined
address-and-datum redirection, the exact staking-credential inequality guard,
and validity after the staking-only change. Rejection of the combined redirect
does not independently establish staking reliance. Fuel exhaustion is not
explicit rejection.

The result covers the original artifact and fixed TxM-007 Claim family within
1,000,000 CEK steps. Both baseline staking credentials are absent; the script
credential remains symbolic rather than bound to the executed program's hash.
The FAIL refutes this guarded first-continuation rejection rule. It does not by
itself establish a vulnerability, full input/output staking preservation,
arbitrary transaction coverage, ledger reachability, or funds loss.

Cancel remains unregistered; its historical inapplicability diagnostic was
unchanged and not rerun. Broader #28/#96 work remains open. No output-minimum
condition, printed transaction witness, or wider artifact admission was added.
Held UP-009/UP-016 and separate milestone proofs were not run.

See the [property guide](README.md) for scope and commands. Raw outputs, source
snapshots, and logs stay local under ignored `formal/output/` directories.

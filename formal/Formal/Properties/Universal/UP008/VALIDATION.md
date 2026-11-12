# UP-008 native integration validation

UP-008 reports an official FAIL for the original vesting Claim fixture: the
fixed-junk rejection obligation is Falsified, and its applicability obligation
is Valid. The compiled enforcing control reports a test-only PASS with both
obligations Valid. Both native obligations still expect Valid.

Implementation commit 1c6b807e7c0a41755b311527062ac1d5cbff74ae records the tested
source, based on foundation 21fbc36. Validation ran on 2026-11-12 with
Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-008 property build and unit suite | Passed; 526 build jobs |
| Affected app/test build | Passed; 625 build jobs |
| Kernel checks | Original mutation and Claim formulas preserved; input structure, output count, and unchanged fields proved |
| Native UP-008 app integration | One FAIL check; Falsified main and Valid applicability; 89.596 seconds |
| Unsupported vault | SKIPPED with unsupported reason; no execution or generated modules |
| Second vesting artifact | SKIPPED with property exclusion reason; no execution or generated modules |
| Compiled enforcing control | PASS; two Valid observations; 20.573-second executor run |
| Qualification controls | Missing, inconclusive, or falsified applicability left either a Valid or Falsified main observation unresolved |
| Affected regressions | UP-007 and UP-014 property suites, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Separate public UP-008 CLI | One FAIL check; Falsified main and Valid applicability; 90.050-second app execution; exit 0 |

Both new suites and seven affected suites passed: nine targeted suites in total.
The aggregate registers 39 suites; this change did not run the full aggregate.
The separate public CLI command is:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json --check UP-008 --timeout-ms 300000
```

Run it from the implementation checkout's `formal/` directory. A zero app exit
means orchestration and evidence retention completed. The property still reports
FAIL when its qualified observations falsify the rule.

## Evidence and control attribution

The original app run retained three generated Lean files, exact input and
property/model metadata, compiler logs, and 18 compiled shared-source snapshots.
Its linked obligations are `junkToken_claim` and `junkToken_claim_applies`.
Source and compiled-file hashes match the saved source index; source hashes also
match the tested implementation. The compiler's falsification exit does not hide
the counterexample log or completed applicability observation.

The enforcing control executes the existing frozen 487-byte compiled program.
Preparation checks its exact blueprint bytes, decoded program, compiler metadata,
handlers, and recomputed Plutus V3 script hash. The frozen Aiken source,
configuration, lockfile, and blueprint digests match their provenance record.
No Aiken rebuild occurred. The control requires the first output to retain the
spent input's script payment credential and contain zero quantity of the exact
`zzzzjunk` / `zzzzjunk` asset. It retains the native formulas, model, four guards,
argument encoding, and CEK bound.

Control evidence has a distinct test identity and null official property/model
binding metadata. Generated Types embeds the executed bytes and computed hash.
The control's `input.json` is its actual blueprint; `reference-input.json` is the
original vesting fixture, marked reference-only. Generated Tx and Checks retain
the native model and propositions. The local `control-project/` snapshot retains
the checked source, configuration, lockfile, and provenance manifest. This test
adds no official catalogue entry.

Qualification controls use in-memory observations to check assessment policy.
They do not execute a solver or establish a validator property. Valid
applicability qualifies the main result; missing, inconclusive, or falsified
support leaves either a passing or failing main observation unresolved.

Initial workflow runs preceded the implementation commit and recorded dirty
base 21fbc36. Their captured sources and 352-file runtime manifest match
1c6b807; the Git label alone does not identify those tested sources. Shared
helpers, generator, assessor, preparation, transaction models, dependency pins,
and historical standalone proof/control implementations are unchanged.

The public CLI ran from clean implementation commit 1c6b807. Its finished index
contains no orchestration errors. Both obligations have complete evidence and
the exact applicability link. It retained three generated Lean files and their
compiler logs, exact input snapshots, and 18 compiled shared-source snapshots.
All source and compiled-file hashes match the saved index, and source hashes
match the working implementation.

The source closure includes shared Continuations without other native properties
or the Cancel model. All 352 runtime source/configuration hashes still match.
App timing excludes launcher preparation.

## Interpretation

The kernel checks establish correspondence with the preserved scoped formulas
and mutation. Initial test build errors concerned list notation and record
layout; those were corrected before successful validation. Generated successful
obligations retain Blaster's `blasterProven` SMT trust. The build also retains
the existing `PlutusCore.UPLC.CekMachine.lean:312` `sorry` warning. This change
neither introduces nor resolves that dependency gap.

The mutation appends a funding input carrying one unit of the fixed junk asset
and `a` lovelace, appends the asset to the first continuation, and returns the
lovelace through a separate appended output. The integer `a` is lovelace, not
token quantity or count. Both validity guards, baseline acceptance, and rejection
after combined address-and-datum redirection remain. That redirect guard does
not independently establish reliance on the continuation's asset composition.
Fuel exhaustion is not explicit rejection.

These results cover the original artifact and fixed TxM-007 Claim family within
1,000,000 CEK steps. The script credential remains symbolic rather than bound to
the executed program's hash. FAIL refutes the guarded fixed-asset rejection rule;
it does not by itself establish a token-count limit, token flooding, locked
funds, a vulnerability, arbitrary transaction coverage, or ledger reachability.

Cancel remains unregistered; its historical inapplicability diagnostic is
unchanged and was not rerun. The configurable token-count limit in #29 and
broader integration work in #96 remain open. No output-minimum condition,
printed transaction witness, or wider artifact admission was added. Held
UP-009/UP-016 and separate milestone proofs were not run.

See the [property guide](README.md) for scope and commands. Raw outputs, source
snapshots, and logs stay local under ignored `formal/output/` directories.

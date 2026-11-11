# UP-011 native integration validation

UP-011 passed the targeted checks below on 2026-11-11. Implementation commit
c323281dfb5805c2b1ef89dc9e205a7721390ac8 records the tested source, based on
foundation fa335001. The environment used Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-011 property build and unit suite | Passed; 518 build jobs |
| Affected app/test build | Passed; 624 build jobs |
| Kernel equivalences | Nine helper equalities, Claim main/applicability correspondence, and mutation field preservation checked |
| Native app integration | One PASS check supported by two Valid observations; 99.924 seconds |
| Claim-only selection | Default, explicit property, and switch-file selection retain only TxM-007; no Cancel binding |
| Unsupported vault | One SKIPPED result with unsupported reason; no generated modules |
| Second vesting artifact | One SKIPPED result with the property exclusion reason; no generated modules |
| Compiled address-ignoring control | Main obligation Falsified/FAIL; applicability Valid/PASS |
| Qualification controls | Missing, inconclusive, or falsified applicability could not qualify a Valid main observation as PASS |
| Affected regressions | Existing UP-013 and UP-004 property suites, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Separate public UP-011 CLI run | One PASS check, two Valid obligations, 107.781-second app execution, and exit 0 |

Both new suites and seven affected regression suites passed. The aggregate now
registers 33 suites; this change did not run the full aggregate.

## Evidence and control attribution

The app run retained three generated Lean files, exact input and property/model
bindings, compiler logs, and a shared source snapshot. The two obligations were
`continuationElsewhere_claim` and `continuationElsewhere_claim_applies`, with the
main result linked to that same model's applicability. No Cancel model entered
the runtime source snapshot or selected combinations.

The separate public CLI invocation used the documented original-fixture command.
It retained both complete Valid observations with the exact applicability link,
three generated Lean files and compiler logs, the exact input snapshot, and
17 compiled shared-source snapshots. Its app elapsed time excludes launcher
preparation. Cancel remains absent from selection and captured runtime imports.

The negative control executes the existing frozen 132-byte address-ignoring
program. The fixture check confirmed its stored blueprint, authored source,
compiler manifest, and lockfile; generated preparation recomputed the script hash
and matched the fixture. No new Aiken compilation was performed.

The control preserves the Claim model, all five premises, mutation, argument
encoding, and 1,000,000-step bound. It requires an inline datum but ignores its
output's address, so redirecting and removing the datum rejects while changing
only the payment credential is accepted. Its Falsified main result has a Valid
applicability witness.

The control has a separate test identity and null official property/binding
metadata. Generated Types embeds the control's actual bytes and computed hash.
Its `input.json` is the executed control blueprint; `reference-input.json` is the
original vesting fixture, explicitly labeled reference-only. Generated Tx and
Checks retain the native model and propositions. These control results do not
claim execution of the original vesting program.

Qualification controls use in-memory observations over the native plans. They
test assessment policy without running a solver or creating validator proof
evidence. Valid main plus missing, inconclusive, or falsified applicability stays
inconclusive; Valid applicability supplies the positive control.

All 324 captured source/configuration hashes matched after targeted validation.
The initial app suite ran before the implementation commit and records dirty
base fa335001. The captured sources and manifest match c323281; the Git label
alone does not identify those tested sources. Shared models, generator, assessor,
preparation code, dependency pins, and historical proof/control implementations
are unchanged. The old standalone guide gained only a native-route note.

## Interpretation

The kernel checks preserve the original helper bodies and both Claim formulas.
The recursive `changeFirst` equality uses list induction; this changes neither
the function nor the statement. Generated results retain Blaster's
`blasterProven` SMT trust boundary and the existing CEK dependency `sorry` warning.

The mutation changes only the first continuation's payment credential and keeps
its staking credential, value, and datum. The separate redirect guard changes
address AND removes datum, so it does not independently establish address
reliance. These results cover the original vesting artifact and fixed TxM-007
Claim family. They do not establish the full address rule, arbitrary output
coverage, or deployed-ledger reachability. Symbolic script credentials and all
five guards remain unchanged.

Cancel remains outside native registration because this fixed model has no
applicable continuation case. Its original standalone propositions and expected
false-applicability diagnostic remain unchanged and were not rerun. Issues #32
and #96 retain broader semantics and integration work. No minimum-ADA condition,
printed transaction witness, or broader artifact admission was added. Held
UP-009/UP-016 proofs and separate milestone proofs were not run.

See the [property guide](README.md) for commands and scope. Generated sources,
raw logs, and snapshots stay local under ignored `formal/output/` folders.

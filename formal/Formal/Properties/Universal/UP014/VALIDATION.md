# UP-014 native integration validation

Implementation commit 266eaba169d2a0473877beea6658dad14f4fcaf2 records the tested
source, based on foundation f6ab123. The targeted suites below ran on 2026-11-11.
On resume on 2026-11-12, all 334 captured source/configuration hashes still matched.
The environment used Lean 4.24.0 and Z3 4.15.2.

| Dependency | Revision |
| --- | --- |
| CardanoLedgerApi | 7b743afcd64c1d2fc6c7ef24b2a260b8b31828fc |
| PlutusCore | 4ef48606303c45225d3ed2e2a87fc50280a763b7 |
| Blaster | 402f6d22c1fc42e6e26255faac77e15b2450e4ab |

## Results

| Check | Observation |
| --- | --- |
| UP-014 property build and unit suite | Passed; 520 build jobs |
| UP-011 property rebuild after helper extraction | Passed; 520 build jobs |
| Affected app/test build | Passed; 638 build jobs |
| Kernel equivalences | Shared helpers, replacement encoding, preserved fields, and both original Claim formulas checked |
| Native UP-014 app integration | One PASS check supported by two Valid observations; 115.135 seconds |
| Unsupported vault | One SKIPPED result with unsupported reason; no generated modules |
| Second vesting artifact | One SKIPPED result with the property exclusion reason; no generated modules |
| Compiled datum-ignoring control | Main obligation Falsified/FAIL; applicability Valid/PASS |
| Qualification controls | Missing, inconclusive, or falsified applicability could not qualify a Valid main observation as PASS |
| UP-011 app/control regression after helper extraction | Passed; original check had two Valid observations; its compiled negative control retained Falsified main/Valid applicability |
| Other affected regressions | UP-011 and UP-013 property suites, discovery, public CLI smoke checks, metadata, selection, and runner controls passed |
| Resumed public UP-014 CLI run on 2026-11-12 | One PASS check, two Valid obligations, 121.485-second app execution, and exit 0 |

Both new suites and eight affected regression suites passed: ten targeted suites
in total. The aggregate registers 35 suites; this change did not run the full
aggregate. Completed solver scenarios were not repeated on resume.

## Shared helper preservation

The nine native continuation helper bodies moved unchanged from UP-011 into
`Formal.Support.Continuations`. Source comparison found the copied helper block
byte-identical apart from its namespace, and the UP-011 statement/applicability
source unchanged. UP-011 retains its nine existing public names as aliases.
Two parity proof lines now unfold the shared module. The successful kernel
checks preserve equivalence with the legacy helpers; no semantic or model change
was needed.

UP-011's native app rerun returned one PASS check with two Valid observations in
100.686 seconds. Its compiled address-ignoring control also retained the expected
Falsified main result and Valid applicability. UP-014's runtime source snapshot
contains the shared helper module without importing the UP-011 property or Cancel
model. Legacy `CandidateHelpers.lean` remains unchanged.

## Evidence and control attribution

The original UP-014 app run retained three generated Lean files, exact input and
property/model bindings, compiler logs, and shared-source snapshots. Its linked
obligations were `continuationOtherDatum_claim` and
`continuationOtherDatum_claim_applies`.

The negative control executes the existing frozen 283-byte `continuation_gate`
program. Its stored blueprint, compiler metadata, and decoded program match the
embedded control. Generated preparation independently recomputed the Plutus V3
script hash and matched the stored value. No new Aiken compilation occurred.

The control preserves the Claim model, five premises, exact datum replacement,
argument encoding, and 1,000,000-step bound. It checks the first output's payment
credential but ignores its datum, so redirection rejects while the datum-only
mutation accepts. Its Falsified main result has a Valid applicability witness.

Control evidence has a distinct test identity and null official property/binding
metadata. Generated Types embeds the control's actual bytes and computed hash.
Its `input.json` is the executed control blueprint; `reference-input.json` is the
original vesting fixture, labeled reference-only. Generated Tx and Checks retain
the native model and propositions.

Qualification controls use in-memory observations over the native plan. They
check assessment policy without running a solver or creating validator proof
evidence. Valid main plus missing, inconclusive, or falsified applicability stays
inconclusive; Valid applicability supplies the positive control.

The initial UP-014 and UP-011 app runs preceded the implementation commit and
record dirty base f6ab123. Their captured sources and runtime manifest match
266eaba; the Git label alone does not identify those tested sources. Shared
generator, assessor, preparation, transaction models, dependency pins, and
historical standalone proof/control implementations are unchanged.

An additional public CLI attempt on 2026-11-11 was interrupted at the owner's
request with exit 130. Its run index remains unfinished and its partial evidence
is preserved. That interruption establishes neither a completed CLI result nor
a proof failure.

The fresh public CLI run on 2026-11-12 completed with both obligations Valid and
their exact applicability link intact. It retained three generated Lean files and
compiler logs, exact input, and 18 compiled shared-source snapshots. The source
closure includes shared Continuations, without the UP-011 property or Cancel
model. Its app elapsed time excludes launcher preparation. All 334 recorded
source/configuration hashes still match after this run.

## Interpretation

The kernel checks preserve the original scoped formulas and helper semantics.
Generated results retain Blaster's `blasterProven` SMT trust boundary and the
existing CEK dependency `sorry` warning. Initial build failures concerned proof
unfolding and Lean layout; those were corrected before the successful runs.

The mutation replaces only the first continuation's inline datum with constructor
0 containing two encoded credentials, an empty vesting list, and three integers.
It preserves the output's address, value, and reference script. The separate
redirect guard changes address AND removes datum, so its rejection does not
independently establish datum reliance. The symbolic replacement fields have
no added semantic schedule-validity constraint.

These results cover the original vesting artifact and fixed TxM-007 Claim family,
not arbitrary or nonempty datum replacements, general datum integrity, or ledger
reachability. Symbolic script credentials, all five guards, and the 1,000,000-step
bound remain unchanged. Cancel remains outside native registration, with its
standalone diagnostic unchanged and not rerun. Broader #35/#96 work remains open.
No minimum-ADA condition, printed witness, or wider artifact admission was added.
Held UP-009/UP-016 and separate milestone proofs were not run.

See the [property guide](README.md) for commands and scope. Generated sources,
raw logs, and snapshots stay local under ignored `formal/output/` folders.

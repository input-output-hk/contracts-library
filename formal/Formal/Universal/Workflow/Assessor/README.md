# Assessor component

Assessor turns requested obligations and recorded execution evidence into a
qualified result. It is a pure transformation: it does not run tools, write files,
select checks, or format a client report.

`assessOne target context plan execution` assesses one property-definition/model
combination. It validates that the plan belongs to that exact context and retains
the original observations. Main/applicability jobs keep distinct module/name
identities and exact support links. Nonempty plans need a property obligation;
support-only or orphan applicability jobs cannot establish a passing check.

## Result contract

The serialized `CheckResult` has six fields:

| Field | Contents |
| --- | --- |
| `target` | Selected validator snapshot; JSON includes identity and a reference to the retained prepared input |
| `check` | Property/version/model association, limitations, and exact property/model metadata snapshots |
| `status` | PASS, FAIL, or INCONCLUSIVE |
| `reasons` | Assessment issues, failed expectations, and generation notes |
| `obligations` | Roles, statements, expected/raw observations, qualified status, evidence completeness, and exact support links |
| `evidence` | References to retained input, generated sources, execution records, logs, and counterexamples |

The coordinator attaches verified evidence paths and saves `check-result.json`.
Large raw logs stay in their evidence files. `target.prepared_input` is null when
the source snapshot was not retained successfully. Evidence is not fabricated for
missing files, and a retention failure leaves the returned result INCONCLUSIVE.

The coordinator also carries an internal typed `notRun` reason for unsupported
generation or validated empty plans, plus a `timedOut` flag from the executor's
state. The app uses these for terminal groups and the run index. They are separate
from the assessed verdict and six-field JSON, and retention failures clear them.
No proof is established by a non-execution reason or timeout flag.

## Qualification rules

- A trustworthy main observation is compared with its declared expectation.
- An applicability obligation must be trustworthy Valid to qualify its linked main
  result. Falsified or unavailable support leaves that property INCONCLUSIVE.
- Changed snapshots, ambiguous attribution, or incomplete module evidence cannot
  establish a passing property. Raw observations remain visible.
- A qualified trustworthy FAIL takes precedence; otherwise incomplete or empty
  attempts remain INCONCLUSIVE. No obligations supplies no passing verdict.

`assessPlan` holds the same qualification policy for the existing bundled CLI.
Reporter delegates to it while retaining its current JSON/text renderer. The
callable core enforces one combination through `Generator.generateOne`; the old
CLI still bundles combinations until orchestration and final output are reviewed.
The future client Reporter will consume CheckResults, preserving their verdicts.
Final branding and batch aggregation are separate work.

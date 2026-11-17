# Shared formal support

This folder holds the small support boundary used across milestones:

| Component | Responsibility |
| --- | --- |
| `Common.lean` | Existing evaluator predicates, including the 5,000,000-step nonacceptance interpretation |
| `Process.lean` | Generic invocation, process state, observations, deadlines, and process-group handling |

[Universal](../Universal/README.md) owns the M1.1 property workflow, preparation,
assessment, reporting, and workflow tests. Its explicit-rejection predicates
remain in [Universal/Support](../Universal/Support/README.md); they are separate
from Common's nonacceptance predicate and keep their existing bounds.

[LinearVesting](../LinearVesting/README.md) owns the M1.2 specification proof suite
and its progress output. Sharing process execution does not make that suite part
of the M1.1 workflow.

# Universal-property candidates

This category contains maintained candidates for reusable validator checks.
The name describes the intended reuse; it does not establish that every property
applies to every validator, model, or protocol.

| Code | Primary claim | Folder |
| --- | --- | --- |
| UP-000 | Existence of a model-valid accepted context within the configured bound | [UP000](UP000/README.md) |
| UP-001 | Nonacceptance over the configured context family | [UP001](UP001/README.md) |
| UP-004 | Existence of a model-valid explicitly rejected context within the configured bound | [UP004](UP004/README.md) |
| UP-011 | Guarded rejection after changing the first continuation's payment credential, with linked applicability | [UP011](UP011/README.md) |
| UP-012 | Experimental signer-removal rejection with explicit premises | [UP012](UP012/README.md) |
| UP-013 | Experimental fully unbounded-range rejection with linked applicability | [UP013](UP013/README.md) |
| UP-015 | Experimental Claim output-reversal acceptance with nonidentity applicability | [UP015](UP015/README.md) |

[Index.lean](Index.lean) imports these seven definitions and points to their metadata.
Each listed entry has one primary definition, metadata, and a README. Concrete check
bindings select the model, evaluator predicates, bounds, and supported target.
The seven registered properties and their models remain experimental. Successful
workflow tests do not establish their general readiness. Definition work remains
in issues #22, #23, #25, #32, #33, #34, and #36; broader model authoring and integration stay in #89
and #96.

Other `UPxxx` folders retain property-owned checks and fixtures in
`Tests/Standalone/`. They do not yet provide a native definition, metadata, or
`Run.lean` merely because their tests live here. See the
[property-bank ownership guide](../README.md#test-ownership) before selecting a
standalone proof job; its model, expected result, and execution limits can differ
from the workflow scenarios.

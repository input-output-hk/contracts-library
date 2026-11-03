# Universal-property candidates

This category contains maintained candidates for reusable validator checks.
The name describes the intended reuse; it does not establish that every property
applies to every validator, model, or protocol.

| Code | Primary claim | Folder |
| --- | --- | --- |
| UP-001 | Nonacceptance over the configured context family | [UP001](UP001/README.md) |
| UP-012 | Experimental signer-removal rejection with explicit premises | [UP012](UP012/README.md) |
| UP-015 | Experimental Claim output-reversal acceptance with nonidentity applicability | [UP015](UP015/README.md) |

[Index.lean](Index.lean) imports the definitions and points to their metadata.
Each folder has one primary definition, metadata, and a README. Concrete check
bindings select the model, evaluator predicates, bounds, and supported target.
The three registered properties and their models remain experimental. Successful
workflow tests do not establish their general readiness. Definition work remains
in issues #23, #33, and #36; broader model authoring and integration stay in #89
and #96.

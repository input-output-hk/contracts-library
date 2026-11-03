# UP-015 output-reversal workflow scenario

This third workflow scenario checks acceptance after swapping the two outputs in
the pinned vesting Claim model. It reuses UP-012's exact compiled validator from
[UP012/Inputs/plutus.json](../UP012/Inputs/plutus.json) and the native
[TxM-007](../../../Formal/TxModels/Definitions/TxM007.lean) constructor. Shared
test-only preparation lives in
[Profiles/LinearVesting.lean](../Profiles/LinearVesting.lean); [Profile.lean](Profile.lean)
adds UP-015's generated obligations without a model copy. The shared adapter also
allows the reviewed vault-demo build using Aiken 1.1.21 with stdlib 3.0.0, retained
independently in
[Profiles/Inputs/linear-vesting-aiken-1.1.21.json](../Profiles/Inputs/linear-vesting-aiken-1.1.21.json).
The allowlist recognizes these two exact artifacts; unknown compiled code remains
unsupported. Property claims, native models, and bounds remain unchanged.

From `formal/`:

```sh
lake exe workflow_up015_tests --unit
lake exe workflow_up015_tests
```

`--unit` checks generation, exact selection, shared preparation, definition
equivalence, unsupported targets, and nonidentity two-output swap conditions
without invoking the solver. The default suite also runs UP-012 and UP-015 against
the same prepared validator/model through the app, exercises unsupported-profile
handling, and runs the negative control. Generated sources and evidence stay under
ignored `formal/output/` directories. The public CLI can select the scenario with:

```sh
./plutus-upv run Workflow/Tests/UP012/Inputs/plutus.json linear_vesting.linear_vesting --check UP-015 --timeout-ms 300000
```

[Definition.lean](../../../Formal/Properties/Universal/UP015/Definition.lean)
defines acceptance preservation when the original and reversed contexts satisfy
`validScriptContext`. Its applicability goal additionally requires a valid
accepted original whose valid reversal changes the output list. This
strengthens the original PR #62 applicability formula without changing the
primary proposition or its 1,000,000 CEK-step allowance. The two-output model makes
reversal a swap. The scenario excludes singleton Cancel reversal and duplicate rotation.

The [negative control](NegativeControl.lean) keeps the same validator, model,
validity premises, bound, and applicability goal. It substitutes the counterfactual
claim that reversal causes explicit rejection. The expected observations are
Falsified/FAIL for that claim and Valid/PASS for applicability. These are test
expectations, not observations reported by this guide. The control uses a test-only
property ID with no official property or combined-check metadata and is absent
from the catalogue.

This scenario tests workflow integration. It does not establish general readiness
of UP-001, UP-012, UP-015, or their models. Wider permutations, arbitrary transaction
shapes, index-sensitive validators, and deployed-ledger reachability remain outside
its scope. General work remains open in [UP-001 #23](https://github.com/no-witness-labs/contracts-library/issues/23),
[UP-012 #33](https://github.com/no-witness-labs/contracts-library/issues/33),
[UP-015 #36](https://github.com/no-witness-labs/contracts-library/issues/36),
[model authoring #89](https://github.com/no-witness-labs/contracts-library/issues/89),
and [candidate integration #96](https://github.com/no-witness-labs/contracts-library/issues/96).

# UP-012 signer-removal workflow scenarios

[UP012/Definition.lean](../../../Formal/Properties/Universal/UP012/Definition.lean)
owns the shared signer-removal statement and applicability predicate.
[Legacy UP-012 provider](../Legacy/Candidates/UP012.lean) instantiates them for Claim
and Cancel, plus native TxM-009 key-datum spend. The original vesting API
preserves the four claims from PR #55 at
`f5cbda7df624f2496dd2e6fe354a0cd15365b923`. [Profile.lean](Profile.lean) composes
these obligations with [shared test-only preparation](../Profiles/LinearVesting.lean),
which owns the pinned artifact guard and imports the native types/models from Formal/TxModels.
UP-015 reuses the same compiled validator input and native TxM-007 Claim model.

From `formal/`:

```sh
lake exe workflow_up012_tests
lake exe workflow_up012_tests --unit
```

`--unit` runs only unit coverage. The default suite also runs
[VaultTests.lean](VaultTests.lean), which checks the two pinned real vault
artifacts through reusable TxM-009 preparation: normal vault PASS, buggy vault FAIL, and
applicability PASS for both are the expected outcomes. These expectations do not
replace execution evidence. The existing vesting identity control remains.

The vesting suite uses the internal legacy fixture driver and expects Valid for Claim signer removal,
Claim applicability, Cancel signer removal, and Cancel applicability. It also
checks explicit rejection of an unsupported artifact. Generated files and
reports stay under `formal/output/`. Public product-command behavior has separate
coverage in `workflow_public_cli_tests` and the recorded public-run validations.

The [negative control](NegativeControl.lean) runs the four component APIs with
the same validator and model, but retains the signer in the generated checks.
The solver must report Falsified/FAIL for both removal obligations and Valid/PASS
for both applicability obligations. The control report must say FAIL/1. These intentional
failures make the enclosing test suite succeed; a timeout or inconclusive result
fails the suite. The control has its own test-only label and is not a CLI candidate.
It leaves the actual candidate, artifact guard, and model unchanged.

## Scope and fixtures

TxM-007/008 preparation remains restricted to two exact unparameterized vesting artifacts.
These are the original PR #55 fixture and the reviewed vault-demo build using
Aiken 1.1.21 with stdlib 3.0.0. Unknown compiled artifacts remain unsupported. This extends the
adapter's allowlist without changing the property claims, native transaction
models, or bounds.
Its supplied Claim and Cancel shapes each have one signer; the operation removes
the first key. The original bound is 1,000,000 steps, and `rejectedWithin` requires
an error or non-unit halt within the bound. Exhaustion does not establish rejection.
Both vesting applicability statements remain separate required jobs.

[Profiles/Vault.lean](../Profiles/Vault.lean) is a compatibility shim for
[reusable TxM-009 preparation](../../Preparation/TxM009.lean). It uses the same
shared property, validity predicate, 1,000,000-step bound, and native constructor.
The datum is `Constr 0 [B owner]`, the redeemer is `Constr 0 []`, and owner,
signer, and recipient vary independently. Selected TxM-009 checks use the reusable
path; the original four-vesting-job `checks`/`jobs` API remains vesting scoped.

[ReusableTests.lean](ReusableTests.lean) uses the fixed
[reusable.json](Inputs/reusable.json) snapshot from the manually built
[preparation-demo](../Projects/preparation-demo) project. Three programs share the
same input schema but have different logic. Expected outcomes are PASS for
`controller_gate`, FAIL for `missing_signature`, and failed applicability with
ERROR for `never_accept`. The last case must never become PASS. Runtime validation
of these new scenarios passed, including the always-rejecting applicability control.

For this example, assume the baseline contains only the intended required signer,
with no unrelated extra signers. The models enforce one signer, but do not infer
who the protocol should authorize. This assumption is descriptive and adds no
Lean premise. Passing the removal check does not establish correct-owner
authorization. The [property scope](../../../Formal/Properties/Universal/UP012/README.md)
and combination metadata retain this limitation; broader required-signer semantics
and universal applicability remain open in [issue #33](https://github.com/no-witness-labs/contracts-library/issues/33).

The generated `Tx.lean` imports and aliases the selected native Claim, Cancel, or spend model,
including their inputs, outputs, and signer.
Blueprint schemas describe datum and redeemer encoding; they do not determine
those transaction contexts. These remain experimental test models. Other
providers can supply different models or use generic contexts, as UP-001 does.

`Inputs/plutus.json` is a self-contained selection of the vesting entries and
supporting schemas from the repository's `onchain/plutus.json`. It preserves the
compiled code and selected handler metadata. `Inputs/compiled-code.txt` and
`Expected/legacy-declarations.lean.txt` are the frozen independent regression oracles.
The current declarations fixture records applications of the shared definition;
DefinitionEquivalence.lean checks their equivalence to the expanded formulas.
`Inputs/unsupported.json` exercises the profile guard.

The independent second-artifact snapshot is
[Profiles/Inputs/linear-vesting-aiken-1.1.21.json](../Profiles/Inputs/linear-vesting-aiken-1.1.21.json).
The original inputs and frozen declarations remain unchanged. The editable
[vault-demo project](../Projects/vault-demo/README.md) builds this second artifact
manually; aggregate workflow tests do not invoke Aiken.

Generated headers identify the current Lean emitter and the original PR/SHA
provenance. Runtime generation uses the profile and candidate module. Edit the
native model and rerun to change the generated scenario sources.
General required-signer semantics
remain outside this experimental scenario, as tracked in issue #33.
UP-001, UP-012, UP-015, and their models remain experimental. Workflow test
coverage does not establish their general readiness; definition work stays in
issues #23, #33, and #36, model authoring in #89, and broader integration in #96.

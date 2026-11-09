# UP-006 standalone counterexample

This fixture tests the unrestricted return-datum goal from PR #51 against the
tracked linear vesting validator. The goal quantifies over every `ScriptContext`:
if the pinned ledger model accepts the context and the compiled validator returns
unit within 1,000,000 CEK steps, every output to its script hash must carry a
schema-conforming inline datum. No transaction-shape premise is added to that goal.

The unrestricted goal is refuted by a checked model counterexample. A concrete
Claim retains five of ten vested tokens at time five. Its original two outputs conform. Moving 2,000,000
lovelace from the beneficiary's payout into a third, datumless output to the same
script hash preserves modeled value balance. The four checked facts establish
model validity and compiled-validator acceptance for the original Claim and the
witness; the all-output datum predicate is false for the witness.

`Counterexample.lean` proves those four concrete facts with Blaster.
`ModelFacts.lean` proves predicate failure and the structural controls by
reflexivity. Ordinary Lean specialization then derives `¬ returnDatumGoal`.
The fixture does not ask SMT to search the unrestricted context domain.

The controls cover a conforming original claim, a conforming inline datum on the
extra output, a malformed inline datum, and another payment credential. The
inline-datum repair is a predicate-only control: adding the original datum to
that ADA-only output would make it an underfunded vesting continuation, so no
validator-acceptance claim is made for that repair.

## Artifact and scope

The fixture freezes `linear_vesting.linear_vesting.spend` and its fallback from
`onchain/plutus.json` at `5562de89c98b95d4a452f08365322ee3b8df0022`, compiled with
Aiken `v1.1.22+39d6b04`:

- Compiled code: 1,404 bytes.
- Plutus V3 hash: `95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a`.

`VerifyFixture.lean` checks the datum schema and all its transitive definitions.
It compares both the embedded code string and actual proof
program with the blueprint, then recomputes Blake2b-224 over the Plutus V3 tag
and complete single-CBOR-encoded code. A change to the selected artifact or datum
schema requires review before updating this fixed fixture.

Types and encodings preserve the public blueprint generator derived from
[sayyadirfanali's PR #44](https://github.com/no-witness-labs/contracts-library/pull/44)
at `99a5734f0e036b6abfb4c3f121a298e35fa2eff6`. The predicate and unrestricted
goal preserve [PR #51](https://github.com/no-witness-labs/contracts-library/pull/51).

This is a bounded statement about the pinned ledger model and compiled program.
It does not establish ledger reachability, deployed exposure, or a vulnerability.
The literal identities in the transaction are model values. The CEK step bound
is not a Cardano CPU or memory budget. Blaster and dependency trust assumptions
remain relevant; the runner prints the theorem axioms for inspection.

## Recorded validation

The retained 2026-11-02 run reports four `Valid` observations in 29.654 seconds,
exit 0, and successful elaboration of `returnDatumFalsified : ¬ returnDatumGoal`.
The log contains no solver `Falsified` line: the property is refuted by specializing
the unrestricted goal to the checked witness. The predicate-failure theorem has
no axioms; the four solver facts and derived negation retain standard axioms and
`Blaster.Tactic.blasterProven`, with no printed `sorryAx` dependency.

The four executable fixture files match the retained pause archive byte for byte.
The raw proof receipt does not contain source hashes, so this comparison records
preserved source identity without claiming a source-bound runtime receipt or a
new solver run. Raw logs, source digests, and the comparison inventory remain in
the local delivery archive. Delivery verification also passed the artifact checker,
structural model facts, and ten existing predicate examples without rerunning SMT.
Final source/integration review remains a delivery gate.

The separately reconciled UP001/UP005/UP006 legacy generator union passed its
47 existing Python tests in 1.509 seconds. That legacy-tool check does not add
Python to this standalone Lean execution path. Final combined-source integration
remains a delivery gate.

## Reproduce

Use the repository's pinned Lean toolchain and `lake-manifest.json`, with Z3
`4.15.2` on `PATH`. From `formal/`, prepare dependencies and the two existing
support modules:

```sh
lake build Blaster Formal.Support.Compatibility Formal.Support.ReturnDatum
mkdir -p .lake/build/lib/lean/tests/UP006
lake env lean -o .lake/build/lib/lean/tests/UP006/Fixture.olean tests/UP006/Fixture.lean
lake env lean -o .lake/build/lib/lean/tests/UP006/ModelFacts.olean tests/UP006/ModelFacts.lean
lake env lean --run tests/UP006/VerifyFixture.lean
lake env lean tests/ReturnDatum.lean
```

Run the four concrete proof obligations with four Lean workers. The file disables
asynchronous elaboration so the obligations run sequentially:

```sh
timeout --kill-after=5s 300s lake env lean --threads=4 tests/UP006/Counterexample.lean
```

Expected evidence is four Blaster `Valid` observations, successful elaboration of
`returnDatumFalsified`, an exit status of zero, and inspected axiom output. All
four solver outcomes are already recorded above. Fixture compilation, structural
controls, and artifact verification alone do not establish those outcomes. A new
attempt that times out or fails is inconclusive and must retain its own evidence.

Checkpoint 2 retains application integration, reusable fixture preparation,
additional targets, and broader model validation. This standalone example
uses the reconciled legacy-generator source without requiring generation at
runtime; those later extensions remain incomplete.

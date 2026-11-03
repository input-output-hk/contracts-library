# UP-001 workflow scenario

This scenario uses [Candidates/UP001.lean](../../../Candidates/UP001.lean) and
its existing 5,000,000-step non-acceptance claim. It keeps raw redeemer data and
the full per-purpose contexts. Fuel exhaustion satisfies this bounded claim.

From `formal/`:

```sh
lake exe workflow_up001_tests
```

The suite invokes the public CLI for a passing vault, deliberately failing
vault, invalid compiled code, and a tiny execution deadline. Expected outcomes
are PASS/0, FAIL/1, and INCONCLUSIVE/2, with reports under `formal/output/`.

## Inputs and source attribution

`Inputs/plutus.json`, `Inputs/aiken.toml`, `Inputs/aiken.lock`, and the two Aiken
source files preserve the exact contents of [PR #47's demo project](https://github.com/no-witness-labs/contracts-library/tree/0dde8ae76e3f8a239bf06685f72327aed4a7c3ef/formal/Universal/Demo/aiken).
The snapshot records Aiken `v1.1.19+e525483` and Apache-2.0 licensing. It does not
require an Aiken rebuild to run the CLI checks.

Blueprint SHA-256:
`afd375487a56be74f83f60e7c94fc2008f6e79b418a7bde3f1575bb4c6c9b426`.

`Inputs/invalid-code.json` deliberately supplies non-hexadecimal code for an
input-error test. `Expected/declarations.lean.txt` preserves the reviewed five
propositions from candidate PR #49 at `b44b6b0757a75d79b79a4de4712523ee3978760e`,
with only the separately approved bound change to literal `5000000`.

The native declaration checks compare against this fixed oracle. They do not
regenerate expected output from the candidate implementation. The complete
workflow suite provides separate solver evidence with Blaster's SMT trust.

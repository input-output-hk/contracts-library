# Tx3 off-chain — devnet tests

This directory holds the **Tx3** reference off-chain and its end-to-end tests.
The tests run against an ephemeral [dolos](https://github.com/txpipe/dolos)
devnet spun up per test by the harness in [`utils.ts`](utils.ts).

## Requirements

- Node.js + the workspace dependencies installed (`npm install` in this folder).
- The **tx3 toolchain** (`trix`, `dolos`, `cshell`) under `~/.tx3`:

  ```bash
  curl -LsSf https://github.com/tx3-lang/tx3up/releases/latest/download/tx3up-installer.sh | sh
  tx3up
  ```

- **dolos ≥ 1.4.0** — see the note below. As of this writing the tx3 toolchain
  still installs **dolos 1.3.2**, which cannot run the Plutus V3 spend tests.

## ⚠️ dolos version requirement (temporary workaround)

Plutus **V3 spend** validators that read the transaction validity range (e.g.
the settings `propose` / `apply` / `close` flows) fail on **dolos ≤ 1.3.2** with
an opaque error:

```bash
-32003 tx script returned failure   (data.logs: [])
```

**Cause:** dolos ≤ 1.3.2 injected the Plutus `POSIXTime` in *seconds* (not
milliseconds) during phase-2 / mempool validation. Time-dependent validators
compare against a millisecond datum, so the check silently fails. Minting works
because it never reads `POSIXTime`.

**Fix:** dolos **v1.4.0** — PR
[#1028](https://github.com/txpipe/dolos/pull/1028) *"Inject Plutus POSIXTime in
milliseconds for mempool validation"*. Any dolos ≥ 1.4.0 (latest is fine) runs
the full suite.

Until the tx3 toolchain ships dolos ≥ 1.4.0, use a newer binary explicitly.

### Option A — point the harness at a newer dolos (no toolchain change)

The harness honors the `DOLOS_BIN` environment variable before falling back to
`~/.tx3/<channel>/bin/dolos`. Download the latest release and set `DOLOS_BIN`:

```bash
# download + extract the latest linux binary (adjust the tag/arch as needed)
curl -LsSf https://github.com/txpipe/dolos/releases/download/v1.6.0/dolos-x86_64-unknown-linux-gnu.tar.gz \
  | tar -xz -C /tmp

# run the tests against it
DOLOS_BIN=/tmp/dolos-x86_64-unknown-linux-gnu/dolos npx vitest run settings/tests/devnet.test.ts --reporter=verbose
```

### Option B — replace the toolchain binary (persistent)

```bash
cp /tmp/dolos-x86_64-unknown-linux-gnu/dolos ~/.tx3/stable/bin/dolos
dolos --version   # should print >= 1.4.0

# afterwards the harness picks it up automatically, no DOLOS_BIN needed:
npx vitest run settings/tests/devnet.test.ts --reporter=verbose
```

Check your current version any time with `dolos --version` or
`~/.tx3/stable/bin/dolos --version`.

## Running the tests

> **Before the tests:** generate the TypeScript client (the tests import it from
> `<protocol-name>/.tx3/codegen/ts-client/...`, which is gitignored). Run from the
> protocol directory where `trix.toml` lives:

```bash
cd offchain/tx3/<protocol-name>
trix codegen --plugin ts-client
```

Then run the tests:

```bash
cd offchain/tx3

# all settings devnet tests
npx vitest run settings/tests/devnet.test.ts --reporter=verbose

# a single test by name
npx vitest run settings/tests/devnet.test.ts -t 'launches, proposes, applies, and closes' --reporter=verbose
```

> **Sandbox note:** the harness spawns dolos from under `~/.tx3` (or a temp dir)
> and binds local TCP ports, so the tests need an unsandboxed / full-network run
> environment.

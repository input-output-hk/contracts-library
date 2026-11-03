# Executor component

Executor consumes a `GenerationPlan`, materializes its modules in a fresh
directory, and runs Lean under one shared time budget. It records observed
solver results and diagnostics. Reporter owns expectation comparison and the
summary; waiver handling remains a later extension.

## API and environment

Import `Workflow.Executor` and call `Workflow.Executor.run plan options`.
The result is `IO (Except String Result)`: invalid plans or configuration return
an error; executed runs retain a structured result and evidence directory.

`Options.leanPath` supplies the prepared Lean dependency search path. Defaults
are `lean`, GNU `timeout`, and a 300,000 ms budget. Executor does not install or
update dependencies. GNU coreutils provides `timeout` and `mktemp`.
This process-supervision profile targets POSIX environments; the descendant
cleanup test uses Linux process information.

Generated modules must have safe, unique module names and arrive in dependency
order. Each job must identify one top-level `theorem` or `def` in its supplied
module. Invalid paths, duplicate jobs, missing modules, and missing declarations
produce errors before execution. The current Generator supplies `Types` before
`Checks`; Executor compiles each module once even when it contains several jobs.

## Budget and isolation

By default, every run receives a new private directory. `Options.outputRoot` selects a parent
folder; when absent, Executor uses the system temporary directory. A selected
parent uses GNU `mktemp` to create a fresh `run.XXXXXXXX` folder.

`Options.directory` lets the coordinator supply a reserved, empty workspace.
Executor rejects a populated workspace before writing sources. The single-check
coordinator creates that directory once and retains it if execution or manifest
writing fails. The product app uses this option to group files under
`formal/output/run.<timestamp>.<unique-id>/validators/<validator>/<check>/`.
Standalone calls and the legacy CLI retain automatic temporary-directory behavior.

The execution manifest records `retention_errors` separately from verification
outcomes. The app preserves an INCONCLUSIVE check result and reports an operational
error when raw log retention fails. Sources, logs, and the manifest use explicit
flushes so buffered write failures are visible before retention is accepted.

Executor writes only inside the new run directory. Lean receives it as both the package root and the first
module search path, and elaborates the supplied source directly.

GNU `timeout --signal=KILL` supervises each command's process group, including
ordinary Lean/Z3 descendants. Each command receives only the remaining shared
budget. A timeout makes the affected jobs inconclusive even if partial output
contains a positive result. Process startup, capture, and metadata handling add
small overhead beyond the nominal command deadline.

The caller owns evidence retention and eventual cleanup. This checkpoint
handles completion and deadlines; it does not add interactive cancellation or
signal-forwarding handlers to a command-line application.

## Observations

Executor reads Lean's JSON diagnostics and attributes them by source file and
declaration range. It recognizes the pinned Blaster's explicit Valid and
Falsified messages, plus its scoped `blasterProven` warning. Counterexample
details accompany a Falsified marker only at the same source position.
The parser accepts indentation on counterexample value lines while preserving
their original text in the evidence.

Silence, foreign-file success, conflicting results, unexpected compiler errors,
unexpected `sorry` warnings, undetermined results, and stopped commands cannot
produce a conclusive observation. Exit zero alone is insufficient. An ordinary
falsified theorem can make Lean exit one; credible scoped diagnostics retain
that as an observed Falsified result, rather than a tool-launch failure.

Run states distinguish `completed`, `timedOut`, `error`, and `noObligations`.
`completed` describes execution, not a passing property. Job observations are
`valid`, `falsified`, or `inconclusive`; each retains the job's declared
expectation, role, applicability reference, and scope. `evidenceComplete` records
that the process finished without module-wide diagnostic or protocol problems;
local job issues remain separate. Stopped, unrun, and exception-path jobs cannot
claim complete evidence. Reporter can preserve earlier trustworthy observations
when a later module fails, without promoting partial output from that module.
The SMT observations inherit Blaster's `blasterProven`
trust boundary and do not assert reconstructed kernel proof terms.

## Evidence

`Result.directory` identifies the retained workspace. It contains the original
generated sources, compiler output files, separate stdout/stderr logs per
module, and `execution.json`. The manifest records the target, commands, search
path, budget, elapsed time, process exit codes, job metadata, diagnostics, and
problems. It contains no PASS/FAIL or waiver decisions.

Each module's `invocation` records the command and exact arguments passed to the
timeout wrapper, the effective working directory, and explicit environment
overrides. The same recorded values drive process launch. An already expired
deadline records no attempted invocation; a launch failure retains its attempted
command. Inherited environment variables stay outside the evidence record.
If writing a later module's logs fails, the manifest retains its attempted command
and earlier observations while the affected jobs remain inconclusive.

When supplied, `propertyDefinition` snapshots the parsed descriptive metadata in
the plan and result. Reporter checks that the execution and plan snapshots agree;
Executor does not use that metadata to choose code, expectations, or outcomes.

Input provenance belongs to the coordinator. The integration harness also
copies its input blueprint into the evidence directory.

## Tests

Component checks and shared arithmetic controls live under
`Workflow/Tests/Unit/`. The optional UP-001 execution wrapper belongs to its
[scenario](../Tests/UP001/README.md).


From `formal/`, with the pinned dependencies and tools prepared:

```sh
lake build Workflow workflow_executor_tests workflow_executor_integration
lake exe workflow_executor_tests
lake exe workflow_executor_integration
```

The isolated fixture harness uses its own native executable as a controlled
compiler. It checks scoped results, falsification details, malformed and foreign
diagnostics, silence, compiler failures, unsafe plans, shared budgets, partial
results, missing tools, and descendant termination. It requires no Input,
Generator, or solver.

The integration harness uses real Lean/Blaster controls: a valid equation and
a falsified equation. Executor recorded both expected observations successfully.
To exercise Input, Generator, and Executor on vesting:

```sh
lake exe workflow_executor_integration ../onchain/plutus.json linear_vesting.linear_vesting 10000
```

The recorded 10-second run timed out with all five UP-001 jobs inconclusive.
That run supplies no passing result for vesting. Its generated sources, input
snapshot, logs, and manifest remain available for diagnosis. At that original
checkpoint, Input and Generator fixture harnesses and all 54 legacy Python
tests also passed.

The original 1,000,000-step [120-second validation run](../Docs/VALIDATION.md)
completed all five checks in 82.1 seconds. The history also records the later
5,000,000-step checkpoint. The earlier timeout remains a valid observation for
its short budget; it is not a failing property result.

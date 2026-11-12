# Legacy fixture retirement validation

The cleanup was validated from source tree
`aca8bbd8740db32c01345a2f37427649104b993d`, based on foundation `ec651ad`.
All 521 tracked source hashes remained unchanged during the regression run.

| Check | Result |
| --- | --- |
| Affected application, fixture, and test targets | Build passed |
| Focused generator, metadata, evidence, report, and property units | Passed in 11.236 seconds |
| `lake exe plutus-upv --help` | Exit 0 |
| `lake exe universal --help` | Expected unknown-executable error, exit 1 |
| `./plutus-upv test` | All 25 suites passed; outer command 867.483 seconds |
| Moved source/data comparison | Eight Lean files retain their logic after planned namespace/import/path and fixture-usage edits; three catalogue JSON files are byte-identical |
| Production import boundary | No legacy implementation modules in the reusable facade or public app closure |
| Changed documentation | 133 local inline/reference links checked |

The aggregate exercised the older independent providers through the internal
`workflow_legacy_fixture` target. Normal, deliberately failing, unsupported,
input-error, applicability, timeout, and evidence controls retained their expected
results. Expected failing control verdicts occur inside passing test suites.

Native property definitions and run declarations, transaction model constructors,
evaluator helpers, and bounds are unchanged. Focused Astra source review found
no remaining blocker after two stale documentation references were fixed.

Run the same local regression from `formal/` with `./plutus-upv test`.
The internal fixture driver is comparison infrastructure, rather than a public
client interface. The earlier `universal` user command is retired.

These results establish the tested cleanup behavior, not general validator safety.
No held UP-009/UP-016 proof attempt or new candidate integration was run.
Raw logs, receipts, and hash comparisons remain in local ignored evidence/output
directories. Existing CEK admission warnings and the SMT trust boundary remain.

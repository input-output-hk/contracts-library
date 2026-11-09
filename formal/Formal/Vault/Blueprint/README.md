# UP-009 vault checkpoint

These modules define one frozen owner-checking vault, its transaction witness
and controls, and the UP-009 existential statement. The proof sources are
unfinished and outside the default `Formal` import graph.

This partial consolidation checkpoint preserves the implementation for continued
work on the shared structure; it does not establish the property. Definition
compilation passed, but the latest proof attempt stopped at the datum-serialization
precheck before any Blaster obligation ran.

See [the UP-009 test guide](../../Properties/Universal/UP009/Tests/Standalone/README.md) for the exact scope,
model assumptions, frozen artifact provenance, error/timeout history, opt-in
commands, and follow-up issues.

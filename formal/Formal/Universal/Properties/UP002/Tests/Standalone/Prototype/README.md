# UP-002 prototype support

**Command paths (2026-11-16).** Examples use the relocated M1.1 paths and
have not been rerun for this documentation update. Recorded outcomes retain
their original revisions, models, and bounds. Run commands from `formal/`
unless a section says otherwise.

This folder contains the retained harness, validator models, unsigned-spend
propositions, and concrete witnesses used by the adjacent UP-002 checks.

From `formal/`, build the definition-only library with:

```sh
lake build UP002Prototype
```

The library's import-module prefix is
`Formal.Universal.Properties.UP002.Tests.Standalone.Prototype`. Declarations
retain the `tests.UP002.Prototype` namespace.
Its glob covers this folder only; symbolic proof jobs remain in `Formal/Universal/Properties/UP002/Tests/Standalone/`
and run explicitly. Building the prototype does not prove its propositions.

See [the UP-002 guide](../../../../../docs/UP002.md) for artifact provenance, exact
claims, bounds, historical evidence, and standalone check commands. Historical
generated-code headers identify the retired generator and its source notes;
the current locations do not change that provenance.

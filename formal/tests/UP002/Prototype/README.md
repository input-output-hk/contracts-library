# UP-002 prototype support

This folder contains the retained harness, validator models, unsigned-spend
propositions, and concrete witnesses used by the adjacent UP-002 checks.

From `formal/`, build the definition-only library with:

```sh
lake build UP002Prototype
```

The library uses the `tests.UP002.Prototype` module and namespace prefix.
Its glob covers this folder only; symbolic proof jobs remain in `tests/UP002/`
and run explicitly. Building the prototype does not prove its propositions.

See [the UP-002 guide](../../../docs/UP002.md) for artifact provenance, exact
claims, bounds, historical evidence, and standalone check commands. Historical
generated-code headers identify the retired generator and its source notes;
the current locations do not change that provenance.

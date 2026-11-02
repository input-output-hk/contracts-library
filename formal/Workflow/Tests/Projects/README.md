# Aiken test projects

Runnable Aiken projects for manual workflow and generated-output inspection.
These projects can support several property scenarios. Check-specific harnesses
and pinned regression inputs remain in their existing scenario folders.

- [vault-demo](vault-demo/README.md): normal and deliberately faulty vaults plus
  linear vesting for inspecting UP-001, UP-012, and UP-015 sources and results.

Build a project's blueprint before invoking `plutus-upv run`. Generated
blueprints/build caches are local; workflow run files stay under `formal/output/`.
The app and aggregate tests do not build these Aiken sources automatically.
The vesting adapter accepts two exact test artifacts and rejects unknown compiled
code. This manual source project does not establish general property/model readiness.

- [preparation-demo](preparation-demo): three manually compiled programs with the same input schema and different authorization logic, used by the reusable TxM-009 pilot.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { axiomAuditSource } from "../scripts/check-property-axioms.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const entry = {
  id: "test",
  title: "Synthetic property",
  category: "test",
  summary: "Test data only.",
  theorems: ["Formal.Sample.first", "Formal.Sample.first"],
};

function fixture(t, properties = [entry]) {
  const directory = mkdtempSync(join(tmpdir(), "axiom-check-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  for (const file of [
    "scripts/check-property-axioms.mjs",
    "scripts/check-catalogue.mjs",
    "docs/property-catalogue/property.schema.json",
    "docs/property-catalogue/validator-metadata.schema.json",
  ]) {
    mkdirSync(dirname(join(directory, file)), { recursive: true });
    cpSync(join(root, file), join(directory, file));
  }
  symlinkSync(
    join(root, "node_modules"),
    join(directory, "node_modules"),
    "dir",
  );
  mkdirSync(join(directory, "formal/Formal/Universal"), { recursive: true });
  writeFileSync(
    join(directory, "formal/Formal/Universal/properties.json"),
    JSON.stringify(properties),
  );
  const bin = join(directory, "bin");
  const log = join(directory, "calls.jsonl");
  mkdirSync(bin);
  // Fake Lake tests process control and cleanup, not Lean's axiom analysis.
  writeFileSync(
    join(bin, "lake"),
    `#!${process.execPath}
const { appendFileSync, readFileSync } = require("node:fs");
const args = process.argv.slice(2);
const source = args[0] === "env" ? readFileSync(args[2], "utf8") : null;
appendFileSync(process.env.AXIOM_TEST_LOG, JSON.stringify({ args, source }) + "\\n");
process.exit(Number(args[0] === "build" ? process.env.AXIOM_BUILD_STATUS || 0 : process.env.AXIOM_LEAN_STATUS || 0));
`,
    { mode: 0o755 },
  );
  return {
    calls: () =>
      existsSync(log)
        ? readFileSync(log, "utf8").trim().split("\n").map(JSON.parse)
        : [],
    run(args = ["Universal"], env = {}) {
      const result = spawnSync(
        process.execPath,
        [join(directory, "scripts/check-property-axioms.mjs"), ...args],
        {
          cwd: tmpdir(),
          encoding: "utf8",
          env: {
            ...process.env,
            PATH: `${bin}:${process.env.PATH}`,
            AXIOM_TEST_LOG: log,
            ...env,
          },
        },
      );
      assert.ifError(result.error);
      return result;
    },
  };
}

test("axiom checker builds one module, deduplicates names, and cleans up", (t) => {
  const check = fixture(t);
  const result = check.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = check.calls();
  assert.deepEqual(calls[0].args, ["build", "+Formal.Universal"]);
  assert.equal(
    calls[1].source,
    axiomAuditSource("Universal", ["Formal.Sample.first"]),
  );
  assert.equal(existsSync(calls[1].args[2]), false);
  assert.match(result.stdout, /1 theorem references/);
});

test("axiom checker rejects invalid JSON structure before building", (t) => {
  const check = fixture(t, [{}]);
  assert.equal(check.run().status, 1);
  assert.deepEqual(check.calls(), []);
});

test("axiom checker rejects injected Lean commands before building", (t) => {
  const check = fixture(t, [
    { ...entry, theorems: ["Formal.Sample.first\n#eval 1"] },
  ]);
  assert.equal(check.run().status, 1);
  assert.deepEqual(check.calls(), []);
});

test("axiom checker propagates build failure without inspecting proofs", (t) => {
  const check = fixture(t);
  assert.equal(check.run(undefined, { AXIOM_BUILD_STATUS: "23" }).status, 23);
  assert.equal(check.calls().length, 1);
});

test("axiom checker propagates Lean rejection and cleans up", (t) => {
  const check = fixture(t);
  assert.equal(check.run(undefined, { AXIOM_LEAN_STATUS: "17" }).status, 17);
  assert.equal(existsSync(check.calls()[1].args[2]), false);
});

test("empty theorem lists explicitly report that no proofs were inspected", (t) => {
  const check = fixture(t, [{ ...entry, theorems: [] }]);
  const result = check.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /no proofs inspected/);
});

for (const args of [[], ["../Universal"], ["Universal", "extra"]]) {
  test(`axiom checker rejects invalid arguments: ${JSON.stringify(args)}`, (t) => {
    const check = fixture(t);
    assert.equal(check.run(args).status, 1);
    assert.deepEqual(check.calls(), []);
  });
}

// These controls use real Lean, not the fake Lake used for process-control tests.
// The synthetic Blaster axiom tests classification, not SMT solver correctness.
for (const [label, declaration, status, message] of [
  [
    "standard proof",
    "theorem caseProof : True := True.intro",
    0,
    /no nonstandard axiom/,
  ],
  [
    "direct sorry",
    "theorem caseProof : True := by sorry",
    1,
    /depends on sorryAx/,
  ],
  [
    "indirect sorry",
    "theorem dependency : True := by sorry\ntheorem caseProof : True := dependency",
    1,
    /depends on sorryAx/,
  ],
  [
    "unrelated sorry",
    "theorem unused : True := by sorry\ntheorem caseProof : True := True.intro",
    0,
    /no nonstandard axiom/,
  ],
  [
    "Blaster trust",
    "theorem caseProof : True := Blaster.Tactic.blasterProven",
    0,
    /Blaster SMT trust dependency/,
  ],
  [
    "unapproved axiom",
    "axiom assumption : True\ntheorem caseProof : True := assumption",
    1,
    /unapproved axiom/,
  ],
  ["missing declaration", "", 1, /Unknown constant/],
]) {
  test(`real Lean axiom policy: ${label}`, (t) => {
    const directory = mkdtempSync(join(tmpdir(), "axiom-policy-control-"));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const file = join(directory, "Control.lean");
    const helper = axiomAuditSource("Unused", []).replace(
      "import Formal.Unused\n",
      "",
    );
    writeFileSync(
      file,
      `${helper}\nnamespace Blaster.Tactic\naxiom blasterProven : ∀ {α : Sort u}, α\nend Blaster.Tactic\nnamespace AxiomPolicyControls\n${declaration}\nend AxiomPolicyControls\nrun_cmd checkPropertyAxioms \`AxiomPolicyControls.caseProof\n`,
    );
    const result = spawnSync("lean", [file], {
      cwd: directory,
      encoding: "utf8",
    });
    assert.ifError(result.error);
    assert.equal(result.status, status, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, message);
  });
}

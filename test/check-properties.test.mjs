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

const root = fileURLToPath(new URL("../", import.meta.url));
const entry = {
  id: "test-property",
  title: "Synthetic test entry",
  category: "test",
  summary: "Test data only.",
  theorems: [
    "Formal.Sample.first",
    "Formal.Sample.second",
    "Formal.Sample.first",
  ],
};

function fixture(t, module = "Universal", properties = [entry]) {
  const directory = mkdtempSync(join(tmpdir(), "properties-check-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  for (const file of [
    "formal/check_properties.sh",
    "scripts/check-properties.mjs",
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

  const write = (name, data) => {
    const file = join(directory, name);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, typeof data === "string" ? data : JSON.stringify(data));
  };
  write(
    `formal/Formal/${module.replaceAll(".", "/")}/properties.json`,
    properties,
  );

  const bin = join(directory, "bin");
  const log = join(directory, "lake-calls.jsonl");
  mkdirSync(bin);
  // Fake Lake isolates checker control flow from actual Lean proof compilation.
  writeFileSync(
    join(bin, "lake"),
    `#!${process.execPath}
const { appendFileSync, readFileSync } = require("node:fs");
const args = process.argv.slice(2);
const source = args[0] === "env" ? readFileSync(args[2], "utf8") : null;
appendFileSync(process.env.CHECKER_LOG,
  JSON.stringify({ args, cwd: process.cwd(), source }) + "\\n");
if (args[0] === "build") process.exit(Number(process.env.CHECKER_BUILD_STATUS || 0));
const known = JSON.parse(process.env.CHECKER_KNOWN_NAMES);
for (const line of source.split("\\n")) {
  if (line.startsWith("#check ") && !known.includes(line.slice(7))) {
    console.error("Unknown theorem: " + line.slice(7));
    process.exit(1);
  }
}
process.exit(Number(process.env.CHECKER_LEAN_STATUS || 0));
`,
    { mode: 0o755 },
  );
  return {
    write,
    calls: () =>
      existsSync(log)
        ? readFileSync(log, "utf8").trim().split("\n").map(JSON.parse)
        : [],
    run: (args = [module], env = {}) => {
      const result = spawnSync(
        "bash",
        [join(directory, "formal/check_properties.sh"), ...args],
        {
          cwd: tmpdir(),
          encoding: "utf8",
          env: {
            ...process.env,
            PATH: `${bin}:${process.env.PATH}`,
            CHECKER_LOG: log,
            CHECKER_KNOWN_NAMES: JSON.stringify(entry.theorems),
            ...env,
          },
        },
      );
      assert.ifError(result.error);
      return result;
    },
  };
}

test("checker uses locked schemas, builds one module, and checks unique names", (t) => {
  const check = fixture(t);
  check.write("formal/Formal/Other/properties.json", "{");
  const result = check.run();
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = check.calls();
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].args, ["build", "+Formal.Universal"]);
  assert.equal(calls[0].cwd, calls[1].cwd);
  assert.deepEqual(calls[1].args.slice(0, 2), ["env", "lean"]);
  assert.equal(
    calls[1].source,
    "import Formal.Universal\n\n#check Formal.Sample.first\n#check Formal.Sample.second\n",
  );
  assert.equal(existsSync(calls[1].args[2]), false);
  assert.match(result.stdout, /Checked 2 theorem references/);
});

for (const [label, data] of [
  ["malformed JSON", "{"],
  ["schema-invalid entries", [{}]],
]) {
  test(`checker rejects ${label} before building`, (t) => {
    const check = fixture(t, "Universal", data);
    const result = check.run();
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.deepEqual(check.calls(), []);
  });
}

test("checker validates metadata in the selected folder", (t) => {
  const check = fixture(t);
  check.write("formal/Formal/Universal/validator-metadata.json", {});
  const result = check.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /validator-metadata.json/);
  assert.deepEqual(check.calls(), []);
});

test("checker propagates build failure without checking theorem names", (t) => {
  const check = fixture(t);
  const result = check.run(undefined, { CHECKER_BUILD_STATUS: "23" });
  assert.equal(result.status, 23);
  assert.equal(check.calls().length, 1);
});

test("checker fails on a missing theorem and removes its temporary file", (t) => {
  const check = fixture(t, "Universal", [
    { ...entry, theorems: ["Formal.Sample.missing"] },
  ]);
  const result = check.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Unknown theorem: Formal.Sample.missing/);
  assert.equal(existsSync(check.calls()[1].args[2]), false);
});

test("checker propagates a Lean process failure", (t) => {
  const check = fixture(t);
  const result = check.run(undefined, { CHECKER_LEAN_STATUS: "17" });
  assert.equal(result.status, 17);
  assert.equal(existsSync(check.calls()[1].args[2]), false);
});

test("checker accepts an empty theorem list and reports zero references", (t) => {
  const check = fixture(t, "Universal", [{ ...entry, theorems: [] }]);
  const result = check.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /Checked 0 theorem references/);
});

test("checker maps dotted modules to nested property-set folders", (t) => {
  const check = fixture(t, "Group.Subgroup");
  const result = check.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(check.calls()[0].args, ["build", "+Formal.Group.Subgroup"]);
});

test("checker rejects a theorem string containing Lean commands", (t) => {
  const check = fixture(t, "Universal", [
    {
      ...entry,
      theorems: ['Formal.Sample.first\n#eval IO.println "unexpected"'],
    },
  ]);
  const result = check.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Invalid fully qualified theorem name/);
  assert.deepEqual(check.calls(), []);
});

for (const args of [[], ["../Universal"], ["--help"], ["Universal", "extra"]]) {
  test(`checker rejects invalid arguments: ${JSON.stringify(args)}`, (t) => {
    const check = fixture(t);
    const result = check.run(args);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Usage:/);
    assert.deepEqual(check.calls(), []);
  });
}

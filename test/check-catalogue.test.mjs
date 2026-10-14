import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { checkCatalogue, validators } from "../scripts/check-catalogue.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const readJson = (file) => JSON.parse(readFileSync(join(root, file), "utf8"));
const sample = readJson("formal/Formal/Universal/properties.json");
const propertySchema = readJson("docs/property-catalogue/property.schema.json");
const metadataSchema = readJson(
  "docs/property-catalogue/validator-metadata.schema.json",
);

// Synthetic structure-only test data, not a real validator snapshot.
const metadata = {
  validator_name: "synthetic.test.spend",
  source_repository: "https://github.com/input-output-hk/contracts-library",
  source_commit: "0".repeat(40),
  file_name: "validators/synthetic_test.ak",
  sha256: "0".repeat(64),
  cbor_hex: "00",
  cbor_format: "single_cbor_hex",
  plutus_version: "v3",
  parameterization_state: "unparameterized",
  applied_parameters: [],
};

function fixture(t, files) {
  const directory = mkdtempSync(join(tmpdir(), "catalogue-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  for (const [name, data] of Object.entries(files)) {
    const file = join(directory, name);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, typeof data === "string" ? data : JSON.stringify(data));
  }
  return directory;
}

test("both Draft 2020-12 schemas compile and accept valid data", () => {
  assert(validators["properties.json"](sample));
  assert(validators["validator-metadata.json"](metadata));
});

for (const [name, data, schema] of [
  ["properties.json", sample, propertySchema.items],
  ["validator-metadata.json", metadata, metadataSchema],
]) {
  for (const field of schema.required) {
    test(`${name} rejects missing ${field}`, () => {
      const value = structuredClone(data);
      delete (Array.isArray(value) ? value[0] : value)[field];
      assert.equal(validators[name](value), false);
    });
  }
  for (const field of Object.keys(schema.properties)) {
    test(`${name} rejects wrong type for ${field}`, () => {
      const value = structuredClone(data);
      (Array.isArray(value) ? value[0] : value)[field] = 42;
      assert.equal(validators[name](value), false);
    });
  }
  test(`${name} rejects unsupported fields`, () => {
    const value = structuredClone(data);
    (Array.isArray(value) ? value[0] : value).unexpected = true;
    assert.equal(validators[name](value), false);
  });
  test(`${name} rejects wrong root type`, () => {
    assert.equal(validators[name](Array.isArray(data) ? {} : []), false);
  });
}

test("property schema accepts arbitrary non-empty categories without a default", () => {
  assert.equal(propertySchema.items.properties.category.enum, undefined);
  assert.equal(propertySchema.items.properties.category.default, undefined);
  for (const category of ["universal", "new-category", "ANY_CATEGORY"]) {
    assert(validators["properties.json"]([{ ...sample[0], category }]));
  }
});

for (const [field, value] of [
  ["category", ""],
  ["theorems", [42]],
]) {
  test(`property schema rejects invalid ${field}`, () => {
    assert.equal(
      validators["properties.json"]([{ ...sample[0], [field]: value }]),
      false,
    );
  });
}

test("property schema permits empty theorem lists and unchanged string rules", () => {
  assert(validators["properties.json"]([]));
  assert(validators["properties.json"]([{ ...sample[0], title: "" }]));
  assert(validators["properties.json"]([{ ...sample[0], theorems: [] }]));
});

for (const [field, value] of [
  ["status", "draft"],
  ["spec_ref", "README.md"],
  ["open_targets", []],
]) {
  test(`property schema rejects removed field ${field}`, () => {
    assert.equal(
      validators["properties.json"]([{ ...sample[0], [field]: value }]),
      false,
    );
  });
}

test("the shared property schema replaces the Universal-local schema", () => {
  assert.equal(
    existsSync(join(root, "formal/Formal/Universal/schema.json")),
    false,
  );
  const script = readFileSync(join(root, "formal/check_properties.sh"), "utf8");
  assert.match(script, /scripts\/check-properties\.mjs/);
  assert.doesNotMatch(script, /npx/);
  const helper = readFileSync(
    join(root, "scripts/check-properties.mjs"),
    "utf8",
  );
  assert.match(
    helper,
    /import \{ checkCatalogue \} from "\.\/check-catalogue\.mjs"/,
  );
});

test("copyable guide template satisfies the property schema", () => {
  const guide = readFileSync(
    join(root, "docs/property-catalogue/property-entries.md"),
    "utf8",
  );
  const template = JSON.parse(guide.match(/```json\n([\s\S]*?)\n```/)[1]);
  assert(validators["properties.json"](template));
});

for (const [field, value] of [
  ["validator_name", ""],
  ["source_repository", "https://github.com/another-owner/contracts-library"],
  ["source_commit", "0".repeat(39)],
  ["source_commit", "g".repeat(40)],
  ["sha256", "0".repeat(63)],
  ["sha256", "g".repeat(64)],
  ["file_name", "/validators/test.ak"],
  ["file_name", "../test.ak"],
  ["file_name", "validators/../test.ak"],
  ["file_name", "validators\\test.ak"],
  ["file_name", "validators/test.txt"],
  ["file_name", "validators/test\n.ak"],
  ["cbor_hex", ""],
  ["cbor_hex", "0"],
  ["cbor_hex", "gg"],
  ["cbor_format", "unknown"],
  ["plutus_version", "v4"],
  ["parameterization_state", "unknown"],
  ["applied_parameters", [42]],
  ["applied_parameters", ["0"]],
  ["applied_parameters", ["gg"]],
  ["compiler_name", ""],
  ["compiler_version", ""],
]) {
  test(`metadata rejects invalid ${field}: ${JSON.stringify(value)}`, () => {
    const state =
      field === "applied_parameters" ? "partially_applied" : "unparameterized";
    assert.equal(
      validators["validator-metadata.json"]({
        ...metadata,
        parameterization_state: state,
        [field]: value,
      }),
      false,
    );
  });
}

test("metadata accepts existing CBOR formats, Plutus versions, and compiler fields", () => {
  for (const cbor_format of metadataSchema.properties.cbor_format.enum) {
    for (const plutus_version of metadataSchema.properties.plutus_version
      .enum) {
      assert(
        validators["validator-metadata.json"]({
          ...metadata,
          cbor_format,
          plutus_version,
          compiler_name: "synthetic",
          compiler_version: "test-only",
        }),
      );
    }
  }
});

for (const state of metadataSchema.properties.parameterization_state.enum) {
  test(`metadata enforces the parameter list for ${state}`, () => {
    const applied = ["partially_applied", "fully_applied"].includes(state);
    const value = { ...metadata, parameterization_state: state };
    assert(
      validators["validator-metadata.json"]({
        ...value,
        applied_parameters: applied ? ["00"] : [],
      }),
    );
    assert.equal(
      validators["validator-metadata.json"]({
        ...value,
        applied_parameters: applied ? [] : ["00"],
      }),
      false,
    );
  });
}

test("file checks classify nested files and ignore unrelated JSON", (t) => {
  const directory = fixture(t, {
    "Universal/properties.json": sample,
    "Synthetic/validator-metadata.json": metadata,
    "unrelated.json": "not JSON",
  });
  const results = checkCatalogue(directory);
  assert.equal(results.length, 2);
  assert(results.every((result) => result.valid));
});

for (const [label, files, expectedStatus] of [
  ["valid data", { "properties.json": sample }, 0],
  ["schema-invalid data", { "properties.json": [{}] }, 1],
  [
    "schema-invalid metadata",
    { "validator-metadata.json": { ...metadata, sha256: "short" } },
    1,
  ],
  ["malformed JSON", { "properties.json": "{" }, 1],
  ["empty catalogue", {}, 1],
]) {
  test(`CLI returns ${expectedStatus} for ${label}`, (t) => {
    const directory = fixture(t, files);
    const result = spawnSync(
      process.execPath,
      [join(root, "scripts/check-catalogue.mjs"), directory],
      { encoding: "utf8", cwd: directory },
    );
    assert.ifError(result.error);
    assert.equal(result.status, expectedStatus, result.stdout + result.stderr);
    if (expectedStatus === 1) assert(result.stderr.length > 0);
    else
      assert.match(
        result.stdout,
        /Schemas valid \(Draft 2020-12\)\.[\s\S]*OK properties\.json/,
      );
  });
}

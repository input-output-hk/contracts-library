import { globSync, readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const root = fileURLToPath(new URL("../", import.meta.url));
const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));
const ajv = new Ajv2020({
  strict: true,
  // Conditional branches constrain fields typed elsewhere in the metadata schema.
  strictTypes: false,
  allErrors: true,
});

export const validators = Object.fromEntries(
  [
    ["properties.json", "property.schema.json"],
    ["validator-metadata.json", "validator-metadata.schema.json"],
  ].map(([name, schema]) => [
    name,
    ajv.compile(readJson(join(root, "docs/property-catalogue", schema))),
  ]),
);

export function checkCatalogue(directory = join(root, "formal/Formal")) {
  const files = globSync("**/{properties.json,validator-metadata.json}", {
    cwd: directory,
  }).sort();
  if (files.length === 0) throw new Error("No catalogue JSON files found.");

  return files.map((file) => {
    try {
      const validate = validators[basename(file)];
      const valid = validate(readJson(join(directory, file)));
      return {
        file,
        valid,
        error: valid ? null : ajv.errorsText(validate.errors),
      };
    } catch (error) {
      return { file, valid: false, error: error.message };
    }
  });
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const results = checkCatalogue(process.argv[2]);
    console.log("Schemas valid (Draft 2020-12).");
    for (const result of results) {
      if (result.valid) console.log(`OK ${result.file}`);
      else console.error(`FAIL ${result.file}: ${result.error}`);
    }
    if (results.some((result) => !result.valid)) process.exitCode = 1;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { checkCatalogue } from "./check-catalogue.mjs";

const formal = fileURLToPath(new URL("../formal/", import.meta.url));
const plainName = /^[\p{L}_][\p{L}\p{N}_']*(?:\.[\p{L}_][\p{L}\p{N}_']*)*$/u;
const isName = (value) => plainName.test(value) && !/\s/u.test(value);

try {
  const [module, ...extra] = process.argv.slice(2);
  if (!module || extra.length > 0 || !isName(module)) {
    throw new Error("Usage: check_properties.sh <module>, e.g. Universal");
  }

  const directory = join(formal, "Formal", ...module.split("."));
  const results = checkCatalogue(directory);
  for (const result of results) {
    if (!result.valid) throw new Error(`${result.file}: ${result.error}`);
  }
  const files = results.filter(
    (result) => basename(result.file) === "properties.json",
  );
  if (files.length === 0) throw new Error("No properties.json files found.");
  const theorems = [
    ...new Set(
      files.flatMap((result) =>
        JSON.parse(readFileSync(join(directory, result.file), "utf8")).flatMap(
          (entry) => entry.theorems,
        ),
      ),
    ),
  ];
  for (const theorem of theorems) {
    if (!isName(theorem) || !theorem.includes(".")) {
      throw new Error(
        `Invalid fully qualified theorem name: ${JSON.stringify(theorem)}`,
      );
    }
  }
  console.log("Catalogue JSON valid.");

  execFileSync("lake", ["build", `+Formal.${module}`], {
    cwd: formal,
    stdio: "inherit",
  });

  const temporary = mkdtempSync(join(tmpdir(), "property-references-"));
  try {
    const file = join(temporary, "TheoremReferences.lean");
    writeFileSync(
      file,
      `import Formal.${module}\n\n${theorems.map((name) => `#check ${name}`).join("\n")}\n`,
    );
    execFileSync("lake", ["env", "lean", file], {
      cwd: formal,
      stdio: "inherit",
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
  console.log(
    `Checked ${theorems.length} theorem references in Formal.${module}.`,
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = error.status || 1;
}

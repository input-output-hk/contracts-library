import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkCatalogue } from "./check-catalogue.mjs";

const formal = fileURLToPath(new URL("../formal/", import.meta.url));
const plainName = /^[\p{L}_][\p{L}\p{N}_']*(?:\.[\p{L}_][\p{L}\p{N}_']*)*$/u;
const isName = (value) => plainName.test(value) && !/\s/u.test(value);

export function axiomAuditSource(module, theorems) {
  return `import Lean
import Formal.${module}

open Lean Elab Command

private def checkPropertyAxioms (name : Name) : CommandElabM Unit := do
  let _ ← getConstInfo name
  let axioms ← collectAxioms name
  let standard : Array Name := #[\`propext, \`Classical.choice, \`Quot.sound]
  let smt : Name := \`Blaster.Tactic.blasterProven
  for axiomName in axioms do
    if axiomName == \`sorryAx then
      throwError m!"{name} depends on sorryAx; any existing-library exception requires explicit review"
    unless standard.contains axiomName || axiomName == smt do
      throwError m!"{name} depends on unapproved axiom {axiomName}; review required"
  if axioms.contains smt then
    logInfo m!"{name}: Blaster SMT trust dependency"
  else
    logInfo m!"{name}: no nonstandard axiom dependencies"

${theorems.map((name) => `run_cmd checkPropertyAxioms \`${name}`).join("\n")}
`;
}

function main() {
  const [module, ...extra] = process.argv.slice(2);
  if (!module || extra.length > 0 || !isName(module)) {
    throw new Error("Usage: node scripts/check-property-axioms.mjs <module>");
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
  execFileSync("lake", ["build", `+Formal.${module}`], {
    cwd: formal,
    stdio: "inherit",
  });
  const temporary = mkdtempSync(join(tmpdir(), "property-axioms-"));
  try {
    const file = join(temporary, "AxiomAudit.lean");
    writeFileSync(file, axiomAuditSource(module, theorems));
    execFileSync("lake", ["env", "lean", file], {
      cwd: formal,
      stdio: "inherit",
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
  console.log(
    theorems.length
      ? `Checked axiom dependencies of ${theorems.length} theorem references.`
      : "No theorem references; no proofs inspected.",
  );
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = error.status || 1;
  }
}

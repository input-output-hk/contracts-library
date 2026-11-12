import Formal.Vesting.Linear.Tests.Runner
import Formal.Vesting.Linear.Tests.AuditFixture
import Formal.Vesting.Linear.Tests.AdmittedFixture

open Lean Formal.Vesting.Linear.Tests

run_cmd do
  let audit ← inspectModule `Formal.Vesting.Linear.Tests.AuditFixture
  let expected := #["Formal.Vesting.Linear.Tests.AuditFixture.dependent",
    "Formal.Vesting.Linear.Tests.AuditFixture.identity"]
  unless audit.theorems.map (·.name) == expected do
    throwError "module audit must include both owned theorems and exclude definitions and imported theorems"
  unless audit.theorems.all (fun t => t.status == "PASS" && t.axioms.isEmpty) do
    throwError "the fixture's ordinary Lean proofs must have no axiom dependencies"
  let admitted ← inspectModule `Formal.Vesting.Linear.Tests.AdmittedFixture
  let expected := #["Formal.Vesting.Linear.Tests.AdmittedFixture.dependent",
    "Formal.Vesting.Linear.Tests.AdmittedFixture.unfinished"]
  unless admitted.theorems.map (·.name) == expected &&
      admitted.theorems.all (fun t => t.status == "PENDING" && t.axioms.contains "sorryAx") do
    throwError "direct and transitive admissions must both be PENDING"

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def proof (status : String := "PASS") : TheoremAudit := {
  name := "Synthetic.example"
  axioms := if status == "PENDING" then #["sorryAx"] else #[]
  status }

private def fake (status : String := "PASS") : RunProcess := fun _ _ args => do
  if args[0]? == some "env" then
    let source := System.FilePath.mk (args.back!)
    let name := source.parent.get!.fileName.get!
    let audit : ModuleAudit := {
      moduleName := s!"Synthetic.{name}", theorems := #[proof status] }
    IO.FS.writeFile (source.parent.get! / "audit.json") ((toJson audit).pretty ++ "\n")
  return { state := .finished, exitCode := some 0, stdout := "synthetic command output\n" }

private def syntheticChecks : Array Check := #[
  { name := "First", moduleName := "Synthetic.First" },
  { name := "Second", moduleName := "Synthetic.Second", dependencies := #["First"] }]

private def checkSummary (result : Result) (complete : Bool) : IO Unit := do
  let summary ← IO.FS.readFile (result.directory / "summary.json")
  let observed := Json.parse summary >>= fun json =>
    json.getObjVal? "complete" >>= Json.getBool?
  require (observed.toOption == some complete) "summary completion must agree with the observed outcomes"

def main : IO UInt32 := do
  let root ← IO.FS.createTempDir
  IO.println s!"Controlled M1.2 runner tests (no validator proofs): {root}"
  let options : Formal.Vesting.Linear.Tests.Options := { workingDirectory := root, checks := syntheticChecks }
  let passing ← runWith options (fake "PASS")
  require (passing.exitCode == 0 && passing.steps.all (·.status == "PASS")) "complete synthetic audit should pass"
  checkSummary passing true
  require (← (passing.directory / "First/build.stdout.log").pathExists) "build stdout must be retained"
  require (← (passing.directory / "First/audit.process.json").pathExists) "audit invocation must be retained"
  require (← (passing.directory / "First/audit.json").pathExists) "theorem audit must be retained separately"
  let pending ← runWith options (fake "PENDING")
  require (pending.exitCode == 2 && pending.steps.all (·.status == "PENDING"))
    "sorry dependencies stay pending while independent module audits continue"
  checkSummary pending false
  require (pending.directory != passing.directory) "runs must have distinct output directories"
  let timedOut ← runWith options (fun _ _ _ => pure { state := .timedOut })
  require (timedOut.exitCode == 2 && timedOut.steps[0]!.status == "TIMEOUT" &&
    timedOut.steps[1]!.status == "BLOCKED") "timeout must not count as proof success"
  checkSummary timedOut false
  let failed ← runWith options (fun _ _ _ => pure { state := .finished, exitCode := some 1 })
  require (failed.steps[0]!.status == "ERROR" && failed.steps[1]!.status == "BLOCKED")
    "build error must block dependent checks"
  let noAudit ← runWith options (fun _ _ _ => pure { state := .finished, exitCode := some 0 })
  require (noAudit.exitCode == 2 && noAudit.steps[0]!.status == "ERROR")
    "exit zero without a theorem audit must not pass"
  let artifactChecks := syntheticChecks.map (fun check => { check with needsArtifact := true })
  let missing ← runWith { options with checks := artifactChecks }
    (fun _ _ _ => throw (IO.userError "missing artifact must prevent subprocess launch"))
  require (missing.steps.all (·.status == "BLOCKED")) "missing flat must block artifact-dependent checks"
  checkSummary missing false
  let empty ← runWith { options with checks := #[] } (fake "PASS")
  require (empty.exitCode == 2) "empty suite must not pass"
  let check := syntheticChecks[0]!
  require (!(assessAudit check { moduleName := "Wrong", theorems := #[proof] }).isOk)
    "wrong module audit must be rejected"
  require (!(assessAudit check { moduleName := check.moduleName, theorems := #[] }).isOk)
    "proof audit must contain theorems"
  require (!(assessAudit check {
    moduleName := check.moduleName,
    theorems := #[{ name := "bad", axioms := #["sorryAx"], status := "PASS" }] }).isOk)
    "admitted theorem must not be labeled PASS"
  require (axiomStatus #[`unknownAssumption] == "ERROR") "unknown axioms must be errors"
  require (axiomStatus #[`Blaster.Tactic.blasterProven] == "PASS") "existing SMT trust boundary should remain explicit"
  let support := { check with support := true }
  require ((assessAudit support { moduleName := check.moduleName, theorems := #[] }).toOption == some "BUILT")
    "support-only modules must be BUILT, not PASS"
  let process ← runProcess { options with lakeCommand := "sh" } ((← IO.monoMsNow) + 100)
    #["-c", "sleep 2"]
  require (process.state == .timedOut) "bounded process runner must classify an actual timeout"
  IO.println "M1.2 runner control tests passed. No milestone proof modules were run."
  return 0

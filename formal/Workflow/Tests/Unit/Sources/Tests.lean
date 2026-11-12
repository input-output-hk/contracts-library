import Workflow.App.Sources

namespace Workflow.Tests.Unit.Sources

open Lean System Workflow Workflow.App

private def ensure (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def plan (source : String) : GenerationPlan :=
  { targetName := "fixture", modules := #[⟨"Generated.Check", source⟩], jobs := #[] }

private def manifest (directory : FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "sources/index.json")))

private def entries (directory : FilePath) : IO (Array Json) := do
  IO.ofExcept ((← IO.ofExcept ((← manifest directory).getObjVal? "sources")).getArr?)

private def expectFailure (label : String) (action : IO α) : IO Unit := do
  let failed ← try action *> pure false catch _ => pure true
  ensure label failed

private def fixture (directory : FilePath) : IO Sources.Options := do
  IO.FS.createDirAll (directory / "Fixture")
  IO.FS.writeFile (directory / "Fixture/Base.lean") "def capturedValue : Nat := 7\n"
  IO.FS.writeFile (directory / "Fixture/Model.lean")
    "/- import Fixture.Fake -/\nimport\n Fixture.Base\n\ndef modelValue : Nat := capturedValue\n"
  return { projectRoot := directory, leanPath := (← IO.getEnv "LEAN_PATH").getD "" }

private def successful : IO Unit := IO.FS.withTempDir fun directory => do
  let options ← fixture directory
  let run := directory / "run"
  let session ← Sources.create run options
  let input := plan "/- nested /- import Fixture.Fake -/ comment -/\nimport Fixture.Model\n"
  let prepared ← Sources.prepare session input
  ensure "sources directory is first" (prepared.startsWith (run / "sources").toString)
  let saved ← entries run
  ensure "transitive imports captured exactly once" (saved.size == 2)
  ensure "dependency compiled first"
    ((saved[0]!.getObjValAs? String "module").toOption == some "Fixture.Base")
  for entry in saved do
    ensure "captured modules compiled" ((entry.getObjValAs? String "state").toOption == some "compiled")
    ensure "compiled hash retained" ((entry.getObjValAs? String "compiled_sha256").isOk)
  IO.FS.writeFile (directory / "Fixture/Base.lean") "def capturedValue : Nat := 99\n"
  let again ← Sources.prepare session input
  ensure "same path reused" (again == prepared)
  ensure "original checkout edits do not replace the saved source"
    ((← IO.FS.readFile (run / "sources/Fixture/Base.lean")) == "def capturedValue : Nat := 7\n")
  ensure "repeated plans retain one copy" ((← entries run).size == 2)
  let check := run / "Check.lean"
  IO.FS.writeFile check "import Fixture.Model\nexample : capturedValue = 7 := rfl\n"
  let result ← IO.Process.output {
    cmd := "lean", args := #[check.toString], cwd := some directory,
    env := #[("LEAN_PATH", some prepared)] }
  ensure s!"generated check imports the compiled snapshot: {result.stderr}{result.stdout}"
    (result.exitCode == 0)
  IO.FS.writeFile (run / "sources/Fixture/Base.lean") "def capturedValue : Nat := 123\n"
  expectFailure "editing a saved source fails closed" (Sources.prepare session input)
  ensure "tampering error retained" ((← manifest run).getObjValAs? String "error" |>.isOk)

private def failureCases : IO Unit := IO.FS.withTempDir fun directory => do
  let options ← fixture directory
  IO.FS.writeFile (directory / "Fixture/Bad.lean") "def broken : Nat := false\n"
  let run := directory / "failed"
  let session ← Sources.create run options
  expectFailure "invalid saved source cannot proceed" (Sources.prepare session (plan "import Fixture.Bad\n"))
  let saved ← entries run
  ensure "failed compile state retained" ((saved[0]!.getObjValAs? String "state").toOption == some "failed")
  ensure "compile command retained" (← (run / "sources/_logs/Fixture/Bad.command.json").pathExists)
  expectFailure "failed session never silently retries" (Sources.prepare session (plan "import Fixture.Bad\n"))
  let binaryRun := directory / "binary"
  let binarySession ← Sources.create binaryRun options
  let _ ← Sources.prepare binarySession (plan "import Fixture.Base\n")
  IO.FS.writeFile (binaryRun / "sources/Fixture/Base.olean") "tampered"
  expectFailure "editing a compiled module fails closed"
    (Sources.prepare binarySession (plan "import Fixture.Base\n"))
  let budgetSession ← Sources.create (directory / "budget") { options with budgetMs := 0 }
  expectFailure "source compilation has a finite separate budget"
    (Sources.prepare budgetSession (plan "import Fixture.Base\n"))
  let missing ← Sources.create (directory / "missing") options
  expectFailure "missing own module is not treated as external"
    (Sources.prepare missing (plan "import Fixture.Missing\n"))
  let malformed ← Sources.create (directory / "malformed") options
  expectFailure "malformed generated imports are reported"
    (Sources.prepare malformed (plan "import\n"))
  let unsafeSession ← Sources.create (directory / "unsafe") options
  expectFailure "quoted traversal module name is rejected"
    (Sources.prepare unsafeSession (plan "import «../Outside»\n"))

end Workflow.Tests.Unit.Sources

def main : IO Unit := do
  Workflow.Tests.Unit.Sources.successful
  Workflow.Tests.Unit.Sources.failureCases
  IO.println "Source bundle tests passed"

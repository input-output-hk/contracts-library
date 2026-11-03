import Workflow.Declarative.Discovery
import Workflow.Declarative.Launcher
import Workflow.Tests.Support

namespace Workflow.Tests.Unit.Declarative.Discovery

open Lean System Workflow Workflow.App Workflow.Declarative
open Workflow.Tests.Support (check)

private def has (source fragment : String) : Bool := (source.splitOn fragment).length > 1

private def accepted (result : Except String α) : IO α := IO.ofExcept result

private def fails (label : String) (action : IO α) : IO Unit := do
  let rejected ← try action *> pure false catch _ => pure true
  check label rejected

private def write (root : FilePath) (relative contents : String) : IO Unit := do
  let path := root / relative
  if let some parent := path.parent then IO.FS.createDirAll parent
  IO.FS.writeFile path contents

private def property (root : FilePath) (code id : String) : IO Unit := do
  let folder := s!"Formal/Properties/Universal/{code}"
  write root (folder ++ "/Run.lean") "def run := ()\n"
  write root (folder ++ "/Definition.lean") "def statement := True\n"
  write root (folder ++ "/metadata.json")
    (Json.mkObj [("identity", Json.mkObj [("id", .str id)])]).compress

private def fixture (root : FilePath) : IO Unit := do
  property root "UP777" "UP-777"
  write root "Formal/TxModels/Definitions/TxM777.lean"
    "namespace Formal.TxModels.TxM777\n  def runnable : Formal.TxModels.Runnable := {}\n"

private def discoveryCases : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let (entries, errors) ← Workflow.Declarative.Discovery.scan root
  check "property discovered without central registration"
    (errors.isEmpty && entries.map (·.id) == #["UP-777"])
  let properties ← Workflow.Declarative.Discovery.propertiesFor root entries #["UP-777"]
  let models ← Workflow.Declarative.Discovery.modelsFor root #["TxM-777"]
  let plan := Workflow.Declarative.Discovery.planSource properties
  let driver := Workflow.Declarative.Discovery.bootstrap properties models
  check "planning evaluates the actual property declaration"
    ((has plan "Discovery.describe") && (has plan "Formal.Properties.Universal.UP777.run"))
  check "planning does not import concrete model implementations"
    (!(has plan "import Formal.TxModels.Definitions"))
  check "bootstrap imports the selected native model and typed export"
    ((has driver "import Formal.TxModels.Definitions.TxM777") &&
      (has driver "Formal.TxModels.TxM777.runnable"))
  check "bootstrap has no central candidate or legacy bridge import"
    (!(has driver "Candidates.") && !(has driver "LegacyUP001"))
  IO.FS.writeBinFile (root / "Formal/TxModels/Definitions/TxM999.lean")
    (ByteArray.mk #[255, 254, 0])
  let selected ← Workflow.Declarative.Discovery.modelsFor root #["TxM-777"]
  check "invalid unused model bytes are neither read nor imported"
    (selected.size == 1 &&
      !(has (Workflow.Declarative.Discovery.bootstrap properties selected) "TxM999"))
  for invalid in #["../TxM-777", "TxM-", "TxM-abc", "TxM-9999"] do
    fails s!"reject invalid or missing selected model {invalid}"
      (Workflow.Declarative.Discovery.modelsFor root #[invalid])
  property root "UP999" "UP-999"
  IO.FS.removeFile (root / "Formal/Properties/Universal/UP999/Definition.lean")
  write root "Formal/Properties/Universal/UP999/Run.lean" "this does not compile\n"
  let (more, _) ← Workflow.Declarative.Discovery.scan root
  check "incomplete unselected source does not block a selected declaration"
    ((← Workflow.Declarative.Discovery.propertiesFor root more #["UP-777"]).size == 1)
  fails "a selected property requires its definition file"
    (Workflow.Declarative.Discovery.propertiesFor root more #["UP-999"])
  write root "Formal/Properties/Universal/UP999/metadata.json" "broken JSON"
  let (valid, malformed) ← Workflow.Declarative.Discovery.scan root
  check "malformed metadata is reported during discovery" (!malformed.isEmpty)
  check "malformed unselected metadata does not load its broken source"
    ((← Workflow.Declarative.Discovery.propertiesFor root valid #["UP-777"]).size == 1)
  property root "UP778" "UP-777"
  let (duplicates, _) ← Workflow.Declarative.Discovery.scan root
  fails "duplicate selected property IDs fail explicitly"
    (Workflow.Declarative.Discovery.propertiesFor root duplicates #["UP-777"])
  check "invalid Lean module paths are rejected"
    ((Workflow.Declarative.Discovery.moduleName "Formal/Bad-Name.lean").isOk == false)
  let goodModule ← accepted
    (Workflow.Declarative.Discovery.moduleName "Formal/Properties/Universal/UP777/Run.lean")
  check "module paths map to the native module"
    (goodModule == "Formal.Properties.Universal.UP777.Run")
  let unicodeDriver := Workflow.Declarative.Discovery.bootstrap properties models #[]
    (some "/tmp/é checks.json")
  check "generated snapshot paths preserve Unicode and spaces"
    ((has unicodeDriver "é checks.json") && !(has unicodeDriver "\\u00e9"))

private def selectionCases : IO Unit := do
  let known := #["UP-777", "UP-999"]
  let explicit ← accepted (parseRequest ["--check", "UP-999", "--check", "UP-777"])
  check "discovery keeps registry order for repeated explicit selection"
    ((← accepted (Workflow.Declarative.Discovery.select explicit known none)) == known)
  let switches ← accepted (parseRequest ["--checks-file", "my checks.json"])
  let source := "{\r\n\"UP-777\":true,\"UP-999\":false\r\n}\r\n"
  check "disabled known properties need no compiled implementation"
    ((← accepted (Workflow.Declarative.Discovery.select switches known (some source))) == #["UP-777"])
  check "an empty enabled selection remains empty"
    ((← accepted (Workflow.Declarative.Discovery.select switches known
      (some "{\"UP-777\":false}"))).isEmpty)
  for invalid in #["[]", "{\"UP-777\":1}", "{\"unknown\":false}"] do
    check "invalid switch values and unknown IDs fail before compilation"
      ((Workflow.Declarative.Discovery.select switches known (some invalid)).isOk == false)

private def indexIn (root : FilePath) : IO Json := do
  let directories ← (root / "output").readDir
  let indices := directories.filter fun item => item.fileName.startsWith "discovery."
  check "startup attempt has one retained preparation directory" (indices.size == 1)
  let some entry := indices[0]? | throw (IO.userError "missing preparation directory")
  IO.ofExcept (Json.parse (← IO.FS.readFile (entry.path / "index.json")))

private def executable (root : FilePath) (source : String) : IO FilePath := do
  let path := root / "fake-lake"
  IO.FS.writeFile path source
  let result ← IO.Process.output { cmd := "chmod", args := #["+x", path.toString] }
  check "test command is executable" (result.exitCode == 0)
  return path

private def retainedFailure : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  write root "Formal/Properties/Universal/UP999/Run.lean" "broken unselected source\n"
  write root "Formal/Properties/Universal/UP999/metadata.json" "broken JSON"
  let lake ← executable root "#!/bin/sh\nprintf 'fixture build failure\\n' >&2\nexit 7\n"
  let exitCode ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1000 } ["--check", "UP-777"]
  check "failed preparation uses operational exit 2" (exitCode == 2)
  let index ← indexIn root
  check "startup failure is retained without a proof verdict"
    ((index.getObjValAs? String "state").toOption == some "failed" &&
      (index.getObjVal? "validators").isOk == false)
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "failed build command is retained" (commands.size == 1)
  let log ← accepted (commands[0]!.getObjValAs? String "stderr")
  check "preparation stderr is retained"
    (has (← IO.FS.readFile log) "fixture build failure")

private def malformedDefault : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  write root "Formal/Properties/Universal/UP999/Run.lean" "broken source\n"
  write root "Formal/Properties/Universal/UP999/metadata.json" "broken JSON"
  let lake ← executable root "#!/bin/sh\nexit 9\n"
  let exitCode ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1000 } []
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "default selection reports malformed property metadata before compiling"
    (exitCode == 2 && commands.isEmpty &&
      (index.getObjValAs? String "state").toOption == some "failed")

private def processCleanup : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let lake ← executable root
    "#!/bin/sh\n/bin/sleep 60 &\nchild=$!\nprintf '%s' \"$child\" > child.pid\nprintf 'child started\\n'\nwait \"$child\"\n"
  let exitCode ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 200 } ["--check", "UP-777"]
  check "preparation timeout uses operational exit 2" (exitCode == 2)
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "preparation timeout and attempted command are recorded"
    ((index.getObjValAs? String "state").toOption == some "failed" && commands.size == 1 &&
      (commands[0]!.getObjValAs? String "state").toOption == some "timedOut")
  for name in #["stdout", "stderr"] do
    let path ← accepted (commands[0]!.getObjValAs? String name)
    check "partial timeout logs remain inspectable" (← (FilePath.mk path).pathExists)
  let child := (← IO.FS.readFile (root / "child.pid")).trim
  let process := FilePath.mk s!"/proc/{child}/stat"
  if ← process.pathExists then
    let fields := (← IO.FS.readFile process).splitOn " "
    check "timeout kills the build descendant rather than leaking it"
      (fields[2]? == some "Z")

private def sharedDeadline : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let lake ← executable root
    "#!/bin/sh\n/bin/sleep 0.6\nif [ \"$1\" = env ]; then\n  printf '{\"properties\":[],\"models\":[\"TxM-777\"]}'\nfi\n"
  let exitCode ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1000 } ["--check", "UP-777"]
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "preparation budget is shared across build and evaluation"
    (exitCode == 2 && commands.size == 2 &&
      (commands[1]!.getObjValAs? String "state").toOption == some "timedOut")

private def finalStartup (ending : String) (expectedRaw : Nat) (allowKilled := false) : IO Unit :=
    IO.FS.withTempDir fun root => do
  fixture root
  let lake ← executable root (
    "#!/bin/sh\nif [ \"$1\" = build ]; then exit 0; fi\n" ++
    "if [ \"$3\" = --run ]; then\n  case \"$4\" in\n" ++
    "    */Plan.lean) printf '{\"properties\":[],\"models\":[]}'; exit 0 ;;\n" ++
    "    */Bootstrap.lean) printf 'final startup control\\n'; " ++ ending ++ " ;;\n" ++
    "  esac\nfi\nexit 0\n")
  let result ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1500 } ["--check", "UP-777"]
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "final invocation failure cannot masquerade as app completion"
    (result == 2 && (index.getObjValAs? String "state").toOption == some "failed")
  let some final := commands.back? | throw (IO.userError "missing final invocation")
  IO.FS.createDirAll "output"
  let retained ← IO.Process.output {
    cmd := "mktemp", args := #["-d", "output/preparation-control.XXXXXXXX"] }
  check "startup control retains its journal" (retained.exitCode == 0)
  let evidence := FilePath.mk retained.stdout.trim
  IO.FS.writeFile (evidence / "index.json") (index.pretty ++ "\n")
  for name in #["stdout", "stderr"] do
    let log ← accepted (final.getObjValAs? String name)
    IO.FS.writeFile (evidence / ("application." ++ name ++ ".log")) (← IO.FS.readFile log)
  IO.println s!"Preparation control evidence: {evidence}"
  check s!"final raw process exit and startup logs are retained: expected {expectedRaw}, observed {(final.getObjValAs? Nat "raw_exit_code").toOption}"
    ((final.getObjValAs? Nat "raw_exit_code").toOption == some expectedRaw ||
      (allowKilled && (final.getObjValAs? Nat "raw_exit_code").toOption == some 137))
  if allowKilled then
    check "late application marker is classified as startup timeout"
      ((final.getObjValAs? String "state").toOption == some "timedOut")
  let stdout ← accepted (final.getObjValAs? String "stdout")
  let stderr ← accepted (final.getObjValAs? String "stderr")
  check "final invocation keeps both log files"
    ((← (FilePath.mk stdout).pathExists) && (← (FilePath.mk stderr).pathExists))
  check "final pre-main output is preserved"
    (has (← IO.FS.readFile stdout) "final startup control")
  let orphan := root / "orphan.pid"
  if ← orphan.pathExists then
    let child := (← IO.FS.readFile orphan).trim
    let process := FilePath.mk s!"/proc/{child}/stat"
    if ← process.pathExists then
      let fields := (← IO.FS.readFile process).splitOn " "
      check "failed startup also kills descendants retaining inherited pipes"
        (fields[2]? == some "Z")

private def finalStartupTimeout : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let lake ← executable root (
    "#!/bin/sh\nif [ \"$1\" = build ]; then exit 0; fi\n" ++
    "if [ \"$3\" = --run ]; then\n  case \"$4\" in\n" ++
    "    */Plan.lean) printf '{\"properties\":[],\"models\":[]}'; exit 0 ;;\n" ++
    "    */Bootstrap.lean) /bin/sleep 60 & child=$!; printf '%s' \"$child\" > final-child.pid; wait \"$child\" ;;\n" ++
    "  esac\nfi\nexit 0\n")
  let result ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1000 } ["--check", "UP-777"]
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  let some final := commands.back? | throw (IO.userError "missing final invocation")
  check "final pre-main compilation shares the preparation deadline"
    (result == 2 && (final.getObjValAs? String "state").toOption == some "timedOut")
  let child := (← IO.FS.readFile (root / "final-child.pid")).trim
  let process := FilePath.mk s!"/proc/{child}/stat"
  if ← process.pathExists then
    let fields := (← IO.FS.readFile process).splitOn " "
    check "final startup timeout kills descendants" (fields[2]? == some "Z")

private def drainerFailure : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let lake ← executable root (
    "#!/bin/sh\nif [ \"$1\" = build ]; then exit 0; fi\n" ++
    "if [ \"$3\" = --run ]; then\n  case \"$4\" in\n" ++
    "    */Plan.lean) ln -s /dev/full \"${4%/*}/application.stdout.log\"; printf '{\"properties\":[],\"models\":[]}'; exit 0 ;;\n" ++
    "    */Bootstrap.lean) printf '0' > \"${4%/*}/app-started.tmp\"; mv \"${4%/*}/app-started.tmp\" \"${4%/*}/app-started\"; printf 'drainer failure control\\n'; /bin/sleep 3 & child=$!; printf '%s' \"$child\" > drain-child.pid; wait \"$child\" ;;\n" ++
    "  esac\nfi\nexit 0\n")
  let started ← IO.monoMsNow
  let result ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 1000 } ["--check", "UP-777"]
  let elapsed := (← IO.monoMsNow) - started
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  let some final := commands.back? | throw (IO.userError "missing final invocation")
  check "an output drainer failure terminates the app and remains operational error"
    (result == 2 && elapsed < 2000 &&
      (index.getObjValAs? String "state").toOption == some "failed" &&
      (final.getObjValAs? String "state").toOption == some "error")
  let pidPath := root / "drain-child.pid"
  if ← pidPath.pathExists then
    let child := (← IO.FS.readFile pidPath).trim
    let process := FilePath.mk s!"/proc/{child}/stat"
    if ← process.pathExists then
      let fields := (← IO.FS.readFile process).splitOn " "
      check "drainer failure kills its descendant group" (fields[2]? == some "Z")

private def appBudgetAfterMarker (fast := false) : IO Unit := IO.FS.withTempDir fun root => do
  fixture root
  let ending := if fast then "exit 0" else "/bin/sleep 1.2; exit 0"
  let lake ← executable root (
    "#!/bin/sh\nif [ \"$1\" = build ]; then exit 0; fi\n" ++
    "if [ \"$3\" = --run ]; then\n  case \"$4\" in\n" ++
    "    */Plan.lean) printf '{\"properties\":[],\"models\":[]}'; exit 0 ;;\n" ++
    "    */Bootstrap.lean) printf '0' > \"${4%/*}/app-started.tmp\"; mv \"${4%/*}/app-started.tmp\" \"${4%/*}/app-started\"; " ++ ending ++ " ;;\n" ++
    "  esac\nfi\nexit 0\n")
  let started ← IO.monoMsNow
  let result ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 500 } ["--check", "UP-777"]
  let elapsed := (← IO.monoMsNow) - started
  let index ← indexIn root
  check "the app's own check budgets replace the preparation budget after main starts"
    (result == 0 && (fast || elapsed ≥ 1000) &&
      (index.getObjValAs? String "state").toOption == some "finished")

private def quoted (text : String) : String :=
  "'" ++ text.replace "'" "'\\''" ++ "'"

private def selectedExportIsChecked : IO Unit := IO.FS.withTempDir fun root => do
  let original ← IO.currentDir
  let support ← IO.FS.realPath ".lake/build/lib/lean/Formal"
  let linked ← IO.Process.output {
    cmd := "cp", args := #["-as", support.toString, (root / "Formal").toString] }
  check "typed fixture retains compiled support without altering the checkout"
    (linked.exitCode == 0)
  for reserved in #["Formal/Properties/Universal/UP777/Definition.olean",
      "Formal/Properties/Universal/UP777/Run.olean", "Formal/TxModels/Definitions/TxM777.olean"] do
    check "reserved test exports do not overwrite maintained compiled modules"
      (!(← (root / reserved).pathExists))
  let inherited := (← IO.getEnv "LEAN_PATH").getD ""
  let paths := inherited.splitOn ":" |>.map fun item =>
    let path := FilePath.mk item
    (if path.isAbsolute then path else original / path).toString
  let search := root.toString ++ ":" ++ String.intercalate ":" paths
  let fixtureFolder := "Formal/Properties/Universal/UP777"
  write root (fixtureFolder ++ "/Definition.lean")
    "namespace Formal.Properties.Universal.UP777\ndef statement (_ : Unit) : Prop := True\nend Formal.Properties.Universal.UP777\n"
  write root (fixtureFolder ++ "/Run.lean")
    "import Formal.Properties.Universal.UP777.Definition\nimport Workflow.Declarative.Types\nnamespace Formal.Properties.Universal.UP777\ndef run : Workflow.Declarative.PropertyRun := { models := #[{ id := \"TxM-777\" }], statement := { definition := ``statement, arguments := #[] }, theoremPrefix := \"fixture\", fuel := 1, scope := \"unselected source control\" }\nend Formal.Properties.Universal.UP777\n"
  write root (fixtureFolder ++ "/metadata.json")
    "{\"identity\":{\"id\":\"UP-777\",\"definition_version\":1},\"formalization\":{\"primary\":\"Formal.Properties.Universal.UP777.statement\"}}"
  write root "Formal/TxModels/Definitions/TxM777.lean"
    "namespace Formal.TxModels.TxM777\ndef context : Unit := ()\nend Formal.TxModels.TxM777\n"
  property root "UP999" "UP-999"
  write root "Formal/Properties/Universal/UP999/Run.lean" "this deliberately cannot compile\n"
  IO.FS.writeBinFile (root / "Formal/TxModels/Definitions/TxM999.lean")
    (ByteArray.mk #[255, 254])
  for source in #[fixtureFolder ++ "/Definition.lean", fixtureFolder ++ "/Run.lean",
      "Formal/TxModels/Definitions/TxM777.lean"] do
    let path := root / source
    let compiled ← IO.Process.output {
      cmd := "lean", args := #["--root=" ++ root.toString, "-o",
        (path.withExtension "olean").toString, path.toString],
      cwd := some original, env := #[("LEAN_PATH", some search)] }
    check s!"typed export fixture compiles without solver execution: {compiled.stdout}{compiled.stderr}"
      (compiled.exitCode == 0)
  let lake ← executable root ("#!/bin/sh\nexport LEAN_PATH=" ++ quoted search ++
    "\nif [ \"$1\" = build ]; then exit 0; fi\nshift\nexec \"$@\"\n")
  let exitCode ← Workflow.Declarative.Launcher.runWith {
    root, outputRoot := root / "output", lakeCommand := lake.toString,
    preparationBudgetMs := some 15000 } ["--check", "UP-777"]
  let index ← indexIn root
  let commands ← accepted do (← index.getObjVal? "commands").getArr?
  check "selected missing runnable fails during typed bootstrap preparation"
    (exitCode == 2 && commands.size == 4 &&
      (index.getObjValAs? String "state").toOption == some "failed")
  let log ← accepted (commands[3]!.getObjValAs? String "stdout")
  let err ← accepted (commands[3]!.getObjValAs? String "stderr")
  check "typed missing-export diagnostics survive startup failure"
    (has ((← IO.FS.readFile log) ++ (← IO.FS.readFile err)) "runnable")
  let planned ← accepted (index.getObjVal? "selected_models")
  check "invalid unselected property and model do not block actual Lean planning"
    ((planned.getObjVal? "models" >>= Json.getArr?).toOption == some #[.str "TxM-777"])

private def maintainedProperties : IO Unit := do
  let (entries, errors) ← Workflow.Declarative.Discovery.scan "."
  check "all maintained properties share discovery" (errors.isEmpty &&
    #["UP-001", "UP-012", "UP-015"].all fun id => entries.any (·.id == id))
  for code in #["UP001", "UP012", "UP015"] do
    let source ← IO.FS.readFile s!"Formal/Properties/Universal/{code}/Run.lean"
    check "Run declarations do not directly import concrete model implementations"
      (!(has source "import Formal.TxModels.Definitions."))
  let properties ← Workflow.Declarative.Discovery.propertiesFor "." entries #["UP-001"]
  let plan := Workflow.Declarative.Discovery.planSource properties
  check "UP001 uses its run declaration without central adapters"
    ((has plan "Formal.Properties.Universal.UP001.Run") &&
      !(has plan "Candidates.") && !(has plan "LegacyUP001"))

def run : IO Unit := do
  discoveryCases
  selectionCases
  retainedFailure
  malformedDefault
  processCleanup
  sharedDeadline
  finalStartup "exit 9" 9
  finalStartup "/bin/sleep 60 & printf '%s' \"$!\" > orphan.pid; exit 1" 1
  finalStartup "exit 0" 0
  finalStartup "printf '9999999999999' > \"${4%/*}/app-started.tmp\"; mv \"${4%/*}/app-started.tmp\" \"${4%/*}/app-started\"; exit 0" 0 true
  finalStartupTimeout
  drainerFailure
  appBudgetAfterMarker true
  appBudgetAfterMarker
  selectedExportIsChecked
  maintainedProperties
  IO.println "Lean property discovery and preparation checks passed."

end Workflow.Tests.Unit.Declarative.Discovery

def main : IO Unit := Workflow.Tests.Unit.Declarative.Discovery.run

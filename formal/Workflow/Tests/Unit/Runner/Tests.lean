import Workflow.Tests.Runner
import Workflow.Tests.Support

open Lean Workflow.Tests
open Workflow.Tests.Support

private def executable (path : System.FilePath) (body : String) : IO Unit := do
  IO.FS.writeFile path ("#!/bin/sh\n" ++ body ++ "\n")
  let result ← IO.Process.output { cmd := "chmod", args := #["+x", path.toString] }
  check "fixture executable permissions" (result.exitCode == 0)

private def summary (root : System.FilePath) : IO Json := do
  let entries ← root.readDir
  let entries := entries.filter (·.fileName.startsWith "test.")
  match entries.toList with
  | [entry] => IO.ofExcept (Json.parse (← IO.FS.readFile (entry.path / "summary.json")))
  | _ => throw (IO.userError "expected one retained test run")

private def suiteRows (report : Json) : IO (Array Json) :=
  IO.ofExcept do (← report.getObjVal? "suites").getArr?

private def logText (row : Json) (key : String) : IO String := do
  IO.FS.readFile (← stringField row key)

def main : IO Unit := do
  Logging.line "Runner controls: build and suite failures below are intentional fixtures."
  IO.FS.withTempDir fun root => do
    let build := root / "fake-lake"
    let stale := root / "stale"
    executable build "printf 'deliberate build failure\\n' >&2\nexit 9"
    executable stale "printf executed > \"$0.executed\""
    let output := root / "build-failure"
    let code ← Runner.runWith {
      lakeCommand := build.toString, binaryDirectory := root, outputRoot := output
      suites := #[{ name := "stale", executable := "stale" }] }
    check "build failure makes test command fail" (code != 0)
    check "build failure cannot run a stale executable"
      (!(← (System.FilePath.mk (stale.toString ++ ".executed")).pathExists))
    let report ← summary output
    check "build failure is reported" ((← stringField report "status") == "failed")
    let entries ← suiteRows report
    check "suite remains explicitly unrun" ((← stringField entries[0]! "state") == "notRun")

    executable build "printf 'build stdout\\n'\nprintf 'build stderr\\n' >&2"
    executable (root / "expected-negative")
      "printf 'expected FAIL and INCONCLUSIVE controls\\n'\nprintf 'fixture stderr\\n' >&2"
    executable (root / "unexpected-failure") "printf 'unexpected failure\\n' >&2\nexit 7"
    executable (root / "after-failure") "printf 'later suite executed\\n'"
    let output := root / "suite-failure"
    let code ← Runner.runWith {
      lakeCommand := build.toString, binaryDirectory := root, outputRoot := output
      suites := #[{ name := "expected-negative", executable := "expected-negative" },
        { name := "unexpected-failure", executable := "unexpected-failure" },
        { name := "after-failure", executable := "after-failure" }] }
    check "unexpected suite failure makes test command fail" (code != 0)
    let report ← summary output
    let entries ← suiteRows report
    check "all independent suites were attempted" (entries.size == 3)
    check "printed FAIL text is not a suite failure"
      ((← stringField entries[0]! "state") == "passed")
    check "nonzero exit is a suite failure" ((← stringField entries[1]! "state") == "failed")
    check "later independent suite runs" ((← stringField entries[2]! "state") == "passed")
    check "stdout log is complete"
      ((← logText entries[0]! "stdoutLog") == "expected FAIL and INCONCLUSIVE controls\n")
    check "stderr log is complete" ((← logText entries[0]! "stderrLog") == "fixture stderr\n")
    let exitCode ← IO.ofExcept do (← entries[1]!.getObjVal? "exitCode").getNat?
    check "failure exit code is retained" (exitCode == 7)

    let output := root / "all-pass"
    let code ← Runner.runWith {
      lakeCommand := build.toString, binaryDirectory := root, outputRoot := output
      suites := #[{ name := "expected-negative", executable := "expected-negative" }] }
    check "expected negative controls allow overall success" (code == 0)
    check "successful summary is retained" ((← stringField (← summary output) "status") == "passed")

    let release := root / "release-stream"
    let streamLog := root / "stream.stdout.log"
    let task ← IO.asTask (Logging.run {
      cmd := "sh"
      args := #["-c", r#"printf 'ready λ\n'; while [ ! -f "$1" ]; do sleep 0.05; done; printf 'done\n'"#,
        "stream-control", release.toString] } (some streamLog)) Task.Priority.dedicated
    let mut visible := false
    try
      for _ in [:100] do
        if ← streamLog.pathExists then
          visible := (← IO.FS.readFile streamLog) == "ready λ\n"
        if visible then break
        IO.sleep 50
    finally
      IO.FS.writeFile release "release"
    let streamed ← IO.ofExcept task.get
    check "output reaches its log before the child exits" visible
    check "stream capture preserves UTF-8 and final output"
      (streamed.exitCode == 0 && streamed.stdout == "ready λ\ndone\n")
  IO.println "Runner failure controls passed (fixture failures above are intentional)."

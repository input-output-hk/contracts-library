import Formal.Vesting.Linear.Tests.Runner

open Formal.Vesting.Linear.Tests

private def usage : String :=
  "Usage: lake exe test_m12 [--list | --help | --timeout-ms N]\n" ++
  "Run the five current linear-vesting milestone modules, with logs and theorem axiom audits.\n" ++
  "The default budget is 300000 ms per module, shared by its build and audit.\n" ++
  "Run from formal/. The existing Scripts/linear_vesting_spend.flat artifact is required for Script and its dependents.\n" ++
  "No artifact is generated automatically. Output: output/m12.*/summary.txt and summary.json.\n" ++
  "Exit 0 means all steps are PASS or BUILT; exit 2 means incomplete or invalid invocation."

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--help"] | ["-h"] => IO.println usage; return 0
  | ["--list"] =>
    for check in checks do
      IO.println (s!"{check.name}: {check.moduleName}" ++
        (if check.support then " (support module)" else " (theorem audit)"))
    return 0
  | [] =>
    try return (← runWith).exitCode
    catch error => IO.eprintln s!"ERROR: {error}"; return 2
  | ["--timeout-ms", value] =>
    if let some timeoutMs := value.toNat? then
      if timeoutMs > 0 then
        try return (← runWith { timeoutMs }).exitCode
        catch error => IO.eprintln s!"ERROR: {error}"; return 2
    IO.eprintln "--timeout-ms must be a positive integer"; return 2
  | _ => IO.eprintln usage; return 2

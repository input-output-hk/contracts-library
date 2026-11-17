import Formal.Universal.Workflow.App.Run
import Formal.Universal.Workflow.Tests.Runner
import Formal.Universal.Workflow.Declarative.Launcher

private def help : String :=
  "Plutus UPV: Universal Property Verifier\n" ++
  "Formal verification of universal properties against compiled Plutus validators.\n\n" ++
  "Usage:\n" ++
  "  " ++ Formal.Universal.Workflow.App.Run.usage ++ "\n" ++
  "  plutus-upv test\n" ++
  "  plutus-upv --help\n\n" ++
  "run uses plutus.json in the current directory when BLUEPRINT is omitted.\n" ++
  "run defaults to all validators and registered checks. --validator and --check may repeat.\n" ++
  "--timeout-ms defaults to 300000 (5 minutes) per validator/check combination.\n" ++
  "test runs all workflow suites with verbose output and retained logs.\n"

def main (args : List String) : IO UInt32 := do
  match args with
  | [] | ["--help"] | ["help"] => IO.print help; return 0
  | ["run", "--help"] | ["test", "--help"] => IO.print help; return 0
  | "run" :: rest =>
    Formal.Universal.Workflow.Declarative.Launcher.run rest
  | ["test"] => Formal.Universal.Workflow.Tests.Runner.run
  | _ => IO.eprint help; return 2

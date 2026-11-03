import Workflow.App.Run
import Workflow.Tests.Runner
import Candidates.Catalogue

private def help : String :=
  "Plutus UPV: Universal Property Verifier\n" ++
  "Formal verification of universal properties against compiled Plutus validators.\n\n" ++
  "Usage:\n" ++
  "  " ++ Workflow.App.Run.usage ++ "\n" ++
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
    Workflow.App.Run.run Candidates.Catalogue.registeredChecks
      (fun id => Candidates.Catalogue.loadCheck id.propertyId id.definitionVersion id.modelId) rest
  | ["test"] => Workflow.Tests.Runner.run
  | _ => IO.eprint help; return 2

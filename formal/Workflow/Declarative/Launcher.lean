import Workflow.App.Run

namespace Workflow.Declarative.Launcher

/-- Keep the public command stable while discovery compiles only its selected declarations. -/
def run (args : List String) : IO UInt32 := do
  match Workflow.App.parseRequest args with
  | .error message => IO.eprintln s!"{message}\nUsage: {Workflow.App.Run.usage}"; return 2
  | .ok _ =>
    try
      let process ← IO.Process.spawn {
        cmd := "python3"
        args := #["scripts/run_properties.py", "--include-legacy"] ++ args.toArray }
      return ← process.wait
    catch error =>
      IO.eprintln s!"Could not start property discovery (python3 is required): {error}"
      return (2 : UInt32)

end Workflow.Declarative.Launcher

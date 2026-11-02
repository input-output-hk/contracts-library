import Workflow.App.Run
import Workflow.Declarative.Catalogue

namespace Workflow.Declarative

/-- Experimental entry point; the bootstrap supplies automatically discovered declarations. -/
def main (properties : Array Property) (models : Array Model) (args : List String) : IO UInt32 := do
  match ← Catalogue.load properties models with
  | .error message => IO.eprintln s!"Property discovery: {message}"; return 2
  | .ok catalogue =>
    if args == ["--list"] then
      for check in catalogue.checks do
        IO.println s!"{check.propertyId} v{check.definitionVersion} / {check.modelId}"
      return 0
    Workflow.App.Run.run catalogue.checks (fun id => pure (catalogue.loadCheck id)) args

end Workflow.Declarative

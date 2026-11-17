import Formal.Universal.Workflow.App.Run
import Formal.Universal.Workflow.Declarative.Catalogue

namespace Formal.Universal.Workflow.Declarative

/-- The bootstrap supplies the selected property and model declarations. -/
def main (properties : Array Property) (models : Array Model) (args : List String)
    (knownProperties : Array String := #[])
    (selectionSnapshot : Option System.FilePath := none)
    (discoveryIndex : Option System.FilePath := none) : IO UInt32 := do
  match ← Catalogue.load properties models with
  | .error message => IO.eprintln s!"Property discovery: {message}"; return 2
  | .ok catalogue =>
    let registry := catalogue.checks
    if args == ["--list"] then
      for check in registry do
        IO.println s!"{check.propertyId} v{check.definitionVersion} / {check.modelId}"
      return 0
    match Formal.Universal.Workflow.App.parseRequest args with
    | .error message => IO.eprintln message; return 2
    | .ok request =>
      try
        let selectionSource ← selectionSnapshot.mapM IO.FS.readFile
        let discoverySource ← discoveryIndex.mapM IO.FS.readFile
        let known := if knownProperties.isEmpty then none else some knownProperties
        let record ← Formal.Universal.Workflow.App.Run.runWith registry
          (fun id => pure (catalogue.loadCheck id))
          request {
            executorOptions := { leanPath := (← IO.getEnv "LEAN_PATH").getD "" }
            knownProperties := known
            selectionSource
            discoverySource }
        IO.print record.text
        return record.exitCode
      catch error =>
        IO.eprintln s!"Property execution could not retain its run: {error}"
        return 2

end Formal.Universal.Workflow.Declarative

import Workflow.Generator.Single
import Formal.TxModels.Runnable

namespace Workflow.Declarative

/-- A property supplies its checked Lean definition and the arguments before the model. -/
structure Goal where
  definition : Lean.Name
  arguments : Array String

/-- Property-owned instructions. Adding an existing model changes only `models`. -/
structure PropertyRun where
  models : Array String
  statement : Goal
  applicability : Option Goal := none
  theoremPrefix : String
  fuel : Nat
  scope : String

/-- Discovery supplies file locations; authors do not repeat them in their declarations. -/
structure Property where
  run : PropertyRun
  runModule : String
  definitionModule : String
  metadataPath : System.FilePath

structure Model where
  moduleName : String
  runnable : Formal.TxModels.Runnable

end Workflow.Declarative

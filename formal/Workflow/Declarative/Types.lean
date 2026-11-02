import Workflow.Generator.Single
import Formal.TxModels.Runnable

namespace Workflow.Declarative

structure Model where
  moduleName : String
  runnable : Formal.TxModels.Runnable

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
  /-- A property can omit a target/model pairing without creating a proof verdict. -/
  skipReason : TargetDescription → Model → Except Generator.Error (Option String) :=
    fun _ _ => pure none
  /-- Preserve property-specific theorem names independently of the context alias. -/
  theoremSuffix : Model → String := fun model =>
    (model.runnable.context.toString.splitOn ".").getLast!

/-- Discovery supplies file locations; authors do not repeat them in their declarations. -/
structure Property where
  run : PropertyRun
  runModule : String
  definitionModule : String
  metadataPath : System.FilePath

end Workflow.Declarative

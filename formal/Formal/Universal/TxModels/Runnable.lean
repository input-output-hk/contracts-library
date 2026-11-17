import Formal.Universal.TxModels.Common
import Formal.Universal.TxModels.Requirements
import Formal.Universal.Workflow.Types.Target

namespace Formal.Universal.TxModels

/-- Input admission belongs to the model, independently of the property using it. -/
inductive Admission where
  | pinnedSpending (compiledPrograms : Array String)
  | spending (inputs : SpendingInputs)
  | unparameterizedV3

/-- A model exposes its existing builder without prescribing its input structure. -/
structure Runnable where
  metadata : Metadata
  context : Lean.Name
  admission : Admission
  /-- A fixed script purpose, when the family has one. -/
  purpose : Option Formal.Universal.Workflow.Purpose := none

end Formal.Universal.TxModels

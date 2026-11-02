import Formal.TxModels.Common
import Formal.TxModels.Requirements

namespace Formal.TxModels

/-- Input admission belongs to the model, independently of the property using it. -/
inductive Admission where
  | pinnedSpending (compiledPrograms : Array String)
  | spending (inputs : SpendingInputs)

/-- A model exposes its existing builder without prescribing its input structure. -/
structure Runnable where
  metadata : Metadata
  context : Lean.Name
  admission : Admission

end Formal.TxModels

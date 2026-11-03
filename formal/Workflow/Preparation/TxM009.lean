import Workflow.Generator.Basic
import Workflow.Preparation.Compatibility
import Workflow.Preparation.Program
import Formal.TxModels.Definitions.TxM009

namespace Workflow.Preparation.TxM009

open Workflow Workflow.Generator

private def modelSource (modulePrefix : String) : String :=
  String.intercalate "\n" [
    "-- Generated for the native TxM-009 input contract.",
    "import Formal.TxModels.Definitions.TxM009", s!"import {modulePrefix}.Types", "",
    s!"namespace {modulePrefix}", "",
    "abbrev SpendLeaves := Formal.TxModels.TxM009.SpendLeaves",
    "abbrev spend := Formal.TxModels.TxM009.spend", "",
    s!"end {modulePrefix}", ""]

/-- Prepare the actual target when its declared spending inputs fit this model. -/
def support (target : TargetDescription) (modulePrefix : String) :
    Except Error (Array GeneratedModule) := do
  Compatibility.check target Formal.TxModels.TxM009.inputs
    |>.mapError fun message => ⟨.unsupported, s!"TxM-009 input requirements: {message}"⟩
  let types ← Program.support target modulePrefix
    |>.mapError fun message => ⟨.invalidPlan, s!"program preparation: {message}"⟩
  return #[types, ⟨s!"{modulePrefix}.Tx", modelSource modulePrefix⟩]

end Workflow.Preparation.TxM009

import Workflow.Declarative.Types
import Workflow.Preparation.Program
import Workflow.Preparation.Compatibility

namespace Workflow.Declarative

open Lean Generator

private def identifier (name : String) : Bool :=
  !name.isEmpty && name.toList.all (fun c => c.isAlphanum || c == '_') &&
    !(name.toList.head!).isDigit

private def contextAlias (model : Model) : String :=
  (model.runnable.context.toString.splitOn ".").getLast!

private def renderGoal (goal : Goal) (run : PropertyRun) (context : String) : String :=
  String.intercalate " " ([goal.definition.toString] ++
    (goal.arguments.map (·.replace "{fuel}" (toString run.fuel))).toList ++ [context])

private def admit (target : TargetDescription) (model : Model) : Except Error Unit := do
  unless target.plutusVersion == model.runnable.metadata.plutus_version do
    throw ⟨.unsupported, "model and validator have different Plutus versions"⟩
  match model.runnable.admission with
  | .spending inputs =>
    Preparation.Compatibility.check target inputs
      |>.mapError fun message => ⟨.unsupported, s!"{model.runnable.metadata.id}: {message}"⟩
  | .pinnedSpending programs =>
    unless target.plutusVersion == "v3" && (target.parameters.getD #[]).isEmpty &&
        target.declaredPurposes == #[.spend] && programs.contains target.compiledCode do
      throw ⟨.unsupported, s!"{model.runnable.metadata.id}: requires an admitted pinned V3 spending program"⟩

/-- Generate the same property definition for any selected, admitted context builder. -/
def generate (propertyId : String) (property : Property) (model : Model) (target : TargetDescription)
    (modulePrefix : String) : Except Error GenerationPlan := do
  let run := property.run
  let modelId := model.runnable.metadata.id
  unless run.models.contains modelId do
    throw ⟨.unsupported, s!"model {modelId} is not enabled by this property"⟩
  let context := contextAlias model
  unless identifier context && identifier run.theoremPrefix &&
      validModuleName model.moduleName && validModuleName property.definitionModule &&
      validModuleName property.runModule do
    throw ⟨.invalidPlan, "invalid model, property, or theorem declaration name"⟩
  if run.fuel == 0 then throw ⟨.invalidPlan, "the property must declare a positive CEK bound"⟩
  admit target model
  let types ← Preparation.Program.support target modulePrefix
    |>.mapError fun message => ⟨.invalidPlan, message⟩
  let tx := String.intercalate "\n" [
    "-- Generated from the selected native model; no model-specific emitter.",
    s!"import {model.moduleName}", s!"import {modulePrefix}.Types", "",
    s!"namespace {modulePrefix}",
    s!"abbrev {context} := {model.runnable.context}",
    s!"end {modulePrefix}", ""]
  let name := s!"{run.theoremPrefix}_{context}"
  let moduleName := s!"{modulePrefix}.Checks"
  let scope := run.scope ++ " Model: " ++ model.runnable.metadata.description
  let main : CheckJob := {
    propertyId
    name, moduleName, statement := renderGoal run.statement run context
    expected := .valid, scope, role := .property, txModelId := some modelId
    applicability := run.applicability.map fun _ => { moduleName, name := name ++ "_applies" } }
  let jobs := match run.applicability with
    | none => #[main]
    | some goal => #[main, {
      propertyId, name := name ++ "_applies", moduleName
      statement := renderGoal goal run context
      expected := .valid, scope, role := .applicability, txModelId := some modelId }]
  let declarations := jobs.map fun job =>
    let definition := if job.role == .property then run.statement.definition
      else (run.applicability.getD run.statement).definition
    s!"theorem {job.name} :\n    {job.statement} := by\n  unfold {definition}\n  blaster\n"
  let checks := String.intercalate "\n" [
    "-- Generated from property-owned Run.lean and the selected native model.",
    "import Blaster", "import Formal.Universal.Execution",
    s!"import {property.definitionModule}", s!"import {property.runModule}", s!"import {modulePrefix}.Types",
    s!"import {modulePrefix}.Tx", "", "set_option Elab.async false", "",
    s!"namespace {modulePrefix}", "open CardanoLedgerApi.V3 (validScriptContext)", "",
    String.intercalate "\n" declarations.toList, s!"end {modulePrefix}", ""]
  return {
    targetName := target.name
    modules := #[types, ⟨s!"{modulePrefix}.Tx", tx⟩, ⟨moduleName, checks⟩]
    jobs, notes := #[scope] }

end Workflow.Declarative

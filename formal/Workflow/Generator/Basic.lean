import Workflow.Types.Target
import Workflow.Types.Jobs

namespace Workflow.Generator

inductive ErrorKind where
  | invalidNamespace | invalidPlan | unsupported
  deriving BEq, Repr

structure Error where
  kind : ErrorKind
  message : String
  deriving Repr

instance : ToString Error where
  toString error := error.message

/-- Ordinary code supplying check-specific generation, with no file or process effects. -/
structure Provider where
  id : String
  generate : TargetDescription → String → Except Error GenerationPlan
  propertyDefinition : Option PropertyDefinition := none
  bindings : Option (Array CheckBinding) := none

/-- The caller chooses an isolated module prefix; generated code never writes it. -/
def generate (provider : Provider) (target : TargetDescription) (modulePrefix : String) :
    Except Error GenerationPlan := do
  unless validModuleName modulePrefix do
    throw ⟨.invalidNamespace, "module prefix must contain capitalized Lean identifier segments"⟩
  let plan ← provider.generate target modulePrefix
  let jobs ← match provider.bindings with
    | none => pure plan.jobs
    | some bindings => plan.jobs.mapM fun job => do
      let some modelId := job.txModelId
        | throw ⟨.invalidPlan, s!"registered model is missing for {job.name}"⟩
      let matching := bindings.filter (fun binding => binding.combinedCheck.txModelId? == some modelId)
      unless matching.size == 1 do
        throw ⟨.invalidPlan, s!"model binding for {job.name} must resolve uniquely"⟩
      let some binding := matching[0]?
        | throw ⟨.invalidPlan, s!"model binding is missing for {job.name}"⟩
      if let some existing := job.binding then
        unless existing == binding do
          throw ⟨.invalidPlan, s!"generator supplied conflicting metadata for {job.name}"⟩
      return { job with binding := some binding }
  for job in jobs do
    if let some binding := job.binding then
      unless binding.txModel.plutusVersion? == some target.plutusVersion do
        throw ⟨.unsupported, s!"transaction model for {job.name} has a different Plutus version than the target"⟩
  let result := { plan with status := if jobs.isEmpty then .noObligations else .ready
                            jobs, propertyDefinition := provider.propertyDefinition
                            bindingsRequired := provider.bindings.isSome || plan.bindingsRequired }
  result.validateBindings.mapError (fun message => { kind := .invalidPlan, message })
  return result

end Workflow.Generator

import Workflow.Types.Target
import Workflow.Types.Jobs

namespace Workflow

/-- One exact property/version/model identity supported by registered code. -/
structure CheckId where
  propertyId : String
  definitionVersion : Int
  modelId : String
  deriving BEq, Repr, Inhabited

/-- Descriptive identity of one configured property/model combination. -/
structure CheckContext where
  propertyDefinition : PropertyDefinition
  binding : CheckBinding
  deriving BEq

def CheckContext.validate (context : CheckContext) (target : TargetDescription) : Except String Unit := do
  let some propertyId := context.propertyDefinition.id?
    | throw "configured check has no property ID"
  context.binding.validate propertyId context.propertyDefinition
  unless context.binding.txModel.plutusVersion? == some target.plutusVersion do
    throw "configured model and target have different Plutus versions"

/-- A single attempt cannot execute obligations attributed to another combination. -/
def CheckContext.validatePlan (context : CheckContext) (target : TargetDescription)
    (plan : GenerationPlan) : Except String Unit := do
  context.validate target
  unless plan.targetName == target.name do throw "generation plan names a different target"
  unless plan.propertyDefinition == some context.propertyDefinition do
    throw "generation plan has a different property definition snapshot"
  unless plan.bindingsRequired do throw "single-check plans must require bindings"
  plan.validateBindings
  unless plan.jobs.isEmpty == (plan.status == .noObligations) do
    throw "generation status and job count disagree"
  if plan.jobs.isEmpty then
    unless plan.modules.isEmpty do throw "an empty single-check plan cannot execute modules"
  else
    unless plan.jobs.any (·.role == .property) do
      throw "single-check plan has no property obligation"
  for job in plan.jobs do
    unless job.binding == some context.binding do
      throw s!"job {job.name} does not belong to the selected check"
    if let some support := job.applicability then
      let supportingJobs := plan.jobs.filter fun candidate =>
        candidate.moduleName == support.moduleName && candidate.name == support.name
      let [candidate] := supportingJobs.toList
        | throw s!"missing or ambiguous applicability obligation for {job.name}"
      unless job.role == .property && candidate.role == .applicability &&
          candidate.expected == .valid && candidate.applicability.isNone &&
          candidate.binding == job.binding do
        throw s!"invalid applicability obligation for {job.name}"
    if job.role == .applicability then
      unless job.expected == .valid && job.applicability.isNone do
        throw s!"invalid applicability metadata for {job.name}"
      unless plan.jobs.any (fun candidate => candidate.role == .property &&
          candidate.applicability == some { moduleName := job.moduleName, name := job.name }) do
        throw s!"unreferenced applicability obligation {job.name}"

end Workflow

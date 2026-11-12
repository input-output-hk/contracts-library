import Workflow.Executor.Types
import Workflow.Types.Check

namespace Workflow.Assessor

open Lean

inductive Status where
  | pass | fail | inconclusive
  deriving BEq, Repr

def Status.label : Status → String
  | .pass => "PASS"
  | .fail => "FAIL"
  | .inconclusive => "INCONCLUSIVE"

inductive NotRunReason where
  | notApplicable | unsupported
  deriving BEq, Repr

def NotRunReason.label : NotRunReason → String
  | .notApplicable => "NOT APPLICABLE"
  | .unsupported => "UNSUPPORTED"

structure Row where
  job : CheckJob
  observed : Option Executor.ObservedResult
  status : Status
  issues : Array String
  evidenceComplete : Bool := false

structure PlanAssessment where
  target : String
  status : Status
  rows : Array Row := #[]
  problems : Array String := #[]
  notes : Array String := #[]
  evidenceDirectory : Option System.FilePath := none
  propertyDefinition : Option PropertyDefinition := none

private def sameIdentity (left right : CheckJob) : Bool :=
  left.name == right.name && left.moduleName == right.moduleName

private def sameMetadata (left right : CheckJob) : Bool :=
  sameIdentity left right && left.propertyId == right.propertyId &&
    left.expected == right.expected && left.statement == right.statement && left.scope == right.scope &&
    left.role == right.role && left.applicability == right.applicability &&
    left.txModelId == right.txModelId && left.binding == right.binding

private def matchesRef (reference : JobRef) (job : CheckJob) : Bool :=
  reference.moduleName == job.moduleName && reference.name == job.name

private structure CheckedObservation where
  row : Row
  trustworthy : Bool

private def observe (execution : Executor.Result)
    (integrityBroken : Bool) (job : CheckJob) : CheckedObservation := Id.run do
  let found := execution.jobs.filter (fun result => sameIdentity result.job job)
  let mut issues : Array String := #[]
  let mut observed := none
  let mut evidenceComplete := false
  if integrityBroken then issues := issues.push "run attribution or generation plan is inconsistent"
  match found.toList with
  | [result] =>
    observed := some result.observed
    evidenceComplete := result.evidenceComplete
    issues := issues ++ result.issues
    unless sameMetadata job result.job do issues := issues.push "job metadata changed during execution"
    unless evidenceComplete do issues := issues.push "execution evidence is incomplete for this obligation"
  | [] => issues := issues.push "missing job observation"
  | _ => issues := issues.push "duplicate job observations"
  if job.role == .applicability then
    unless job.expected == .valid do issues := issues.push "applicability must expect Valid"
    unless job.applicability.isNone do issues := issues.push "applicability obligations cannot require another applicability obligation"
  let trustworthy := issues.isEmpty && evidenceComplete &&
    (observed == some .valid || observed == some .falsified)
  let mut status := Status.inconclusive
  if trustworthy then
    if job.role == .applicability then
      if observed == some .valid then status := .pass
      else issues := issues.push "no applicable scenario in this model"
    else
      status := match observed with
        | some .valid => if job.expected == .valid then .pass else .fail
        | some .falsified => if job.expected == .falsified then .pass else .fail
        | _ => .inconclusive
  else if issues.isEmpty then
    issues := issues.push (if job.role == .applicability then "applicability was not established"
      else "no conclusive property observation")
  return { row := { job, observed, status, issues, evidenceComplete }, trustworthy }

/-- Qualify properties using their explicit applicability links, then aggregate results. -/
def assessPlan (plan : GenerationPlan) (execution : Executor.Result) : PlanAssessment := Id.run do
  let mut problems := execution.problems
  unless execution.state == .completed do
    problems := problems.push s!"execution did not complete: {reprStr execution.state}"
  if plan.jobs.isEmpty then problems := problems.push "no obligations were executed"
  let mut integrityProblems : Array String := #[]
  if plan.propertyDefinition != execution.propertyDefinition then
    integrityProblems := integrityProblems.push "property definition metadata changed during execution"
  if let .error message := plan.validateBindings then
    integrityProblems := integrityProblems.push s!"invalid model binding: {message}"
  if plan.jobs.isEmpty != (plan.status == .noObligations) then
    integrityProblems := integrityProblems.push "generation status and job count disagree"
  if execution.state == .noObligations && !plan.jobs.isEmpty then
    integrityProblems := integrityProblems.push "execution reports no obligations for a nonempty plan"
  if plan.jobs.any (fun job => (plan.jobs.filter (sameIdentity job)).size != 1) then
    integrityProblems := integrityProblems.push "duplicate requested job"
  if execution.jobs.any (fun result => !plan.jobs.any (sameIdentity result.job)) then
    integrityProblems := integrityProblems.push "execution contains observations for unrequested jobs"
  problems := problems ++ integrityProblems
  let observations := plan.jobs.map (observe execution (!integrityProblems.isEmpty))
  let mut rows := #[]
  for observation in observations do
    let mut row := observation.row
    if row.job.role == .property then
      if let some reference := row.job.applicability then
        let supports := observations.filter (fun support => matchesRef reference support.row.job)
        let reason := match supports.toList with
          | [support] =>
            if support.row.job.role != .applicability ||
                support.row.job.propertyId != row.job.propertyId then
              some "invalid applicability reference: expected an applicability obligation for this property"
            else if support.row.job.txModelId != row.job.txModelId ||
                support.row.job.binding != row.job.binding then
              some "invalid applicability reference: property and support use different model bindings"
            else if support.trustworthy && support.row.observed == some .valid then none
            else if support.trustworthy && support.row.observed == some .falsified then
              some "no applicable scenario in this model"
            else some "applicability was not established"
          | _ => some "invalid applicability reference: missing or ambiguous obligation"
        if let some reason := reason then
          row := { row with status := .inconclusive, issues := row.issues.push reason }
    rows := rows.push row
  let status := if rows.any (·.status == .fail) then Status.fail
    else if !problems.isEmpty || rows.isEmpty || rows.any (·.status == .inconclusive) then .inconclusive
    else .pass
  return { target := plan.targetName, status, rows, problems, notes := plan.notes
           evidenceDirectory := execution.directory, propertyDefinition := plan.propertyDefinition }


/-- One assessed combination, with raw logs retained through evidence references. -/
structure CheckResult where
  target : TargetDescription
  check : CheckContext
  status : Status
  reasons : Array String
  obligations : Array Row
  evidence : Array System.FilePath := #[]
  notRun : Option NotRunReason := none
  timedOut : Bool := false

private def expectedText : ExpectedResult → String
  | .valid => "valid"
  | .falsified => "falsified"

private def observedText : Executor.ObservedResult → String
  | .valid => "valid"
  | .falsified => "falsified"
  | .inconclusive => "inconclusive"

private def checkJson (context : CheckContext) : Json :=
  let original := context.binding.combinedCheck.toJson
  let value := match original with
    | .obj _ => original
    | _ => Json.mkObj [("combined_check", original)]
  (value.setObjVal! "property_metadata" context.propertyDefinition.toJson).setObjVal!
    "tx_model_metadata" context.binding.txModel.toJson

/-- Machine-readable check data; final report layout is a separate responsibility. -/
def CheckResult.toJson (result : CheckResult) : Json :=
  let input := do
    let directory ← result.evidence[0]?
    let path := directory / "input.json"
    if result.evidence.contains path then some path else none
  let obligations := result.obligations.map fun row => Json.mkObj [
    ("module", .str row.job.moduleName), ("name", .str row.job.name),
    ("role", .str row.job.role.label), ("statement", .str row.job.statement),
    ("expected", .str (expectedText row.job.expected)),
    ("observed", row.observed.map (fun value => Json.str (observedText value)) |>.getD .null),
    ("status", .str row.status.label), ("reasons", Lean.toJson row.issues),
    ("evidenceComplete", .bool row.evidenceComplete),
    ("applicability", row.job.applicability.map (fun reference => Json.mkObj [
      ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null)]
  Json.mkObj [
    ("target", Json.mkObj [("name", .str result.target.name),
      ("plutus_version", .str result.target.plutusVersion),
      ("prepared_input", input.map (fun path => Json.str path.toString) |>.getD .null)]),
    ("check", checkJson result.check), ("status", .str result.status.label),
    ("reasons", Lean.toJson result.reasons), ("obligations", .arr obligations),
    ("evidence", Lean.toJson (result.evidence.map (·.toString)))]

/-- Assess one selected combination without interpreting descriptive prose. -/
def assessOne (target : TargetDescription) (context : CheckContext)
    (plan : GenerationPlan) (execution : Executor.Result) : CheckResult := Id.run do
  let assessed := assessPlan plan execution
  let mut status := assessed.status
  let mut reasons := assessed.problems ++ assessed.notes
  let mut obligations := assessed.rows
  if let .error message := context.validatePlan target plan then
    let reason := s!"invalid selected check: {message}"
    status := .inconclusive
    reasons := reasons.push reason
    obligations := obligations.map fun row =>
      { row with status := .inconclusive, issues := row.issues.push reason }
  for row in obligations do
    for issue in row.issues do
      reasons := reasons.push s!"{row.job.name}: {issue}"
    if row.status == .fail && row.issues.isEmpty then
      let observed := row.observed.map observedText |>.getD "missing"
      reasons := reasons.push
        s!"{row.job.name}: expected {expectedText row.job.expected}, observed {observed}"
  return { target, check := context, status, reasons, obligations }

def failure (target : TargetDescription) (context : CheckContext) (message : String) : CheckResult :=
  { target, check := context, status := .inconclusive, reasons := #[message], obligations := #[] }

end Workflow.Assessor

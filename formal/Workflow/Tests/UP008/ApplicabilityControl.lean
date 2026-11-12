import Workflow.Assessor
import Workflow.Tests.Support
import Workflow.Tests.UP008.Fixture

namespace Workflow.Tests.UP008.ApplicabilityControl

open Workflow Workflow.Tests.Support

/-- In-memory observations test qualification only; no compiler or solver is run. -/
def unit : IO Unit := do
  let catalogue ← Fixture.catalogue
  let input ← Fixture.input
  for id in Fixture.selection do
    let configured ← IO.ofExcept (catalogue.loadCheck id)
    let original ← IO.ofExcept ((Generator.generateOne configured input.target "Generated").mapError toString)
    let plan := { original with
      targetName := s!"UP-008-applicability-control.{id.modelId}"
      jobs := original.jobs.map fun job =>
        { job with propertyId := "UP-008-applicability-control", binding := none }
      propertyDefinition := none
      bindingsRequired := false }
    let some main := plan.jobs[0]? | throw (IO.userError "applicability control: missing property job")
    let some support := plan.jobs[1]? | throw (IO.userError "applicability control: missing support job")
    check "applicability control uses both native obligations and their exact support link"
      (plan.jobs.size == 2 && main.role == .property && support.role == .applicability &&
       main.applicability == some { moduleName := support.moduleName, name := support.name } &&
       support.applicability.isNone && plan.validateBindings.isOk)
    for mainObserved in #[Executor.ObservedResult.valid, .falsified] do
      let baseline : Executor.Result := {
        state := .completed
        jobs := plan.jobs.map fun job => {
          job, observed := if job.role == .property then mainObserved else .valid
          evidenceComplete := true } }
      let qualified := Assessor.assessPlan plan baseline
      let mainStatus := if mainObserved == .valid then Assessor.Status.pass else .fail
      check "controlled Valid applicability qualifies the observed main verdict"
        (qualified.status == mainStatus && qualified.problems.isEmpty && qualified.rows.size == 2 &&
         qualified.rows.all fun row => row.job.expected == .valid &&
          if row.job.role == .property then
            row.status == mainStatus && row.observed == some mainObserved
          else row.status == .pass && row.observed == some .valid)
      for observed in #[some Executor.ObservedResult.falsified, some .inconclusive, none] do
        let jobs := match observed with
          | some value => baseline.jobs.map fun row =>
              if row.job.role == .applicability then { row with observed := value } else row
          | none => baseline.jobs.filter (·.job.role == .property)
        let assessment := Assessor.assessPlan plan { baseline with jobs }
        let some mainRow := assessment.rows[0]?
          | throw (IO.userError "applicability control: missing assessed property")
        let some supportRow := assessment.rows[1]?
          | throw (IO.userError "applicability control: missing assessed support")
        check "controlled missing, inconclusive, or falsified applicability makes the check inconclusive"
          (assessment.status == .inconclusive && assessment.problems.isEmpty &&
           assessment.rows.size == 2 && assessment.rows.all (·.status == .inconclusive) &&
           mainRow.observed == some mainObserved && mainRow.evidenceComplete &&
           supportRow.observed == observed &&
           supportRow.evidenceComplete == observed.isSome)
        let reason := if observed == some .falsified then "no applicable scenario in this model"
          else "applicability was not established"
        check "controlled applicability failure explains the unqualified property result"
          (mainRow.issues.contains reason && !supportRow.issues.isEmpty)
        if observed.isNone then
          check "missing applicability is retained as a missing observation"
            (supportRow.issues.contains "missing job observation")
        check "controlled observations create no execution evidence or official attribution"
          (assessment.evidenceDirectory.isNone && assessment.propertyDefinition.isNone &&
           baseline.modules.isEmpty && baseline.directory.isNone &&
           assessment.rows.all fun row =>
            row.job.propertyId == "UP-008-applicability-control" && row.job.binding.isNone)
  IO.println "UP008 applicability qualification controls passed (in-memory observations only)."

end Workflow.Tests.UP008.ApplicabilityControl

import Workflow.Assessor
import Workflow.Executor
import Workflow.Tests.Support
import Workflow.Tests.UP013.Fixture

namespace Workflow.Tests.UP013.NegativeControl

open Lean Workflow Workflow.Tests.Support

private def propertyId := "UP-013-always-accepting-control"

private def note :=
  "TEST ONLY: replace the admitted program with a synthetic always-accepting program; retain the original UP-013 claim, full-range mutation, selected model, validity premises, applicability obligation, argument encoding, and 1,000,000 CEK-step bound."

private def program :=
  "def program : Program := .Program (.Version 1 1 0) (.Lam \"ctx\" (.Const .Unit))"

private def replaceOnce (source before after : String) : Except String String := do
  unless (source.splitOn before).length == 2 do
    throw "always-accepting control: expected exactly one generated declaration"
  return source.replace before after

/-- Transform an already admitted native plan without broadening production admission. -/
def plan (original : GenerationPlan) (target : TargetDescription) : Except String GenerationPlan := do
  let some types := original.modules[0]? | throw "always-accepting control: missing Types module"
  let some job := original.jobs[0]? | throw "always-accepting control: missing native obligation"
  let some support := original.jobs[1]? | throw "always-accepting control: missing applicability obligation"
  unless types.name.endsWith ".Types" && original.modules.size == 3 && original.jobs.size == 2 &&
      job.role == .property && support.role == .applicability &&
      job.applicability == some { moduleName := support.moduleName, name := support.name } &&
      support.applicability.isNone do
    throw "always-accepting control: unexpected native plan layout"
  let source ← replaceOnce types.source
    s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr target.compiledCode.toLower}"
    program
  let hash ← Preparation.Program.scriptHashHex target.compiledCode.toLower
  let source ← replaceOnce source
    s!"/-- Hash computed from the supplied script bytes. -/\ndef scriptHashHex : String := {reprStr hash}"
    "-- Synthetic test program: no compiled-script hash is claimed."
  return { original with
    targetName := s!"{propertyId}.{job.txModelId.getD "missing"}"
    modules := original.modules.set! 0 { types with source := s!"-- {note}\n{source}" }
    jobs := original.jobs.map fun job => { job with propertyId, binding := none }
    notes := original.notes.push note
    bindingsRequired := false
    propertyDefinition := none }

private def prepared : IO (Array (GenerationPlan × GenerationPlan)) := do
  let catalogue ← Fixture.catalogue
  let input ← Fixture.input
  Fixture.selection.mapM fun id => do
    let configured ← IO.ofExcept (catalogue.loadCheck id)
    let original ← IO.ofExcept ((Generator.generateOne configured input.target "Generated").mapError toString)
    return (original, ← IO.ofExcept (plan original input.target))

def unit : IO Unit := do
  let input ← Fixture.input
  let hash ← IO.ofExcept (Preparation.Program.scriptHashHex input.target.compiledCode.toLower)
  for (original, control) in ← prepared do
    check "always-accepting control preserves both native obligations" (control.jobs.size == 2)
    for index in [:original.jobs.size] do
      let some before := original.jobs[index]? | throw (IO.userError "missing native obligation")
      let some after := control.jobs[index]? | throw (IO.userError "missing control obligation")
      check "always-accepting control preserves the native claim, model, role, support link, and scope"
        (after.name == before.name && after.moduleName == before.moduleName &&
         after.statement == before.statement && after.scope == before.scope &&
         after.txModelId == before.txModelId && after.expected == .valid &&
         after.role == before.role && after.applicability == before.applicability &&
         after.propertyId == propertyId && after.binding.isNone)
    let some after := control.jobs[0]? | throw (IO.userError "missing control property obligation")
    check "always-accepting control preserves native model aliases and proof declarations"
      (control.modules[1]?.map (·.source) == original.modules[1]?.map (·.source) &&
       control.modules[2]?.map (·.source) == original.modules[2]?.map (·.source))
    check "always-accepting control clears official attribution and retains test-only identity"
      (after.propertyId == propertyId && after.binding.isNone &&
       control.targetName == s!"{propertyId}.{after.txModelId.getD "missing"}" &&
       control.propertyDefinition.isNone && !control.bindingsRequired &&
       control.validateBindings.isOk && control.notes.contains note)
    let some types := control.modules[0]? | throw (IO.userError "missing control Types module")
    let source := types.source
    check "always-accepting source contains only the synthetic program and no original script hash"
      ((source.splitOn program).length == 2 &&
       (source.splitOn "singleCborEncodedScriptFromHexM").length == 1 &&
       (source.splitOn "def scriptHashHex").length == 1 &&
       (source.splitOn input.target.compiledCode.toLower).length == 1 &&
       (source.splitOn hash).length == 1)
    check "always-accepting control retains context encoding and explicit rejection semantics"
      ((source.splitOn "def args (ctx : ScriptContext) : List Term := [toTerm ctx]").length == 2 &&
       (source.splitOn "cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)").length == 2 &&
       (source.splitOn "Formal.Support.rejectedWithin program (args ctx) fuel").length == 2)
  IO.println "UP013 always-accepting control preparation checks passed."

def run : IO Unit := do
  let input ← Fixture.input
  let mut directories : Array System.FilePath := #[]
  for (_, control) in ← prepared do
    let some job := control.jobs[0]? | throw (IO.userError "missing control obligation")
    let modelId := job.txModelId.getD "missing"
    startCase s!"UP013: always-accepting control for {modelId}"
      "FAIL; Falsified property obligation and Valid applicability obligation"
      "native plan -> synthetic program -> Executor.run -> Assessor.assessPlan" 300000
    let execution ← IO.ofExcept (← Executor.run control {
      leanPath := (← IO.getEnv "LEAN_PATH").getD ""
      outputRoot := some "output"
      budgetMs := 300000 })
    let assessment := Assessor.assessPlan control execution
    let some directory := execution.directory
      | throw (IO.userError "always-accepting control: missing evidence directory")
    directories := directories.push directory
    IO.FS.writeFile (directory / "original-input.json") input.sourceText
    let result := Json.mkObj [
      ("control", .str propertyId), ("scope", .str note),
      ("target", .str control.targetName),
      ("program", .str "synthetic always-accepting program"),
      ("reference_input", .str "original-input.json"),
      ("reference_input_role", .str "reference only; the synthetic program was executed"),
      ("status", .str assessment.status.label),
      ("propertyDefinition", .null),
      ("obligations", .arr (assessment.rows.map fun row => Json.mkObj [
        ("name", .str row.job.name), ("tx_model", .str modelId),
        ("property", .str row.job.propertyId), ("role", .str row.job.role.label),
        ("combinedCheck", .null), ("transactionModel", .null),
        ("applicability", row.job.applicability.map (fun reference => Json.mkObj [
          ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null),
        ("statement", .str row.job.statement), ("status", .str row.status.label),
        ("expected", .str "valid"),
        ("observed", row.observed.map (fun observed => Json.str
          (if observed == .valid then "valid" else if observed == .falsified then "falsified"
            else "inconclusive")) |>.getD .null),
        ("evidenceComplete", .bool row.evidenceComplete)]))]
    IO.FS.writeFile (directory / "control-result.json") (result.pretty ++ "\n")
    check "always-accepting control retains the original input only as a reference"
      ((← IO.FS.readFile (directory / "original-input.json")) == input.sourceText &&
       !(← (directory / "input.json").pathExists) &&
       (← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "control-result.json")))) == result)
    IO.println s!"ControlResult: {directory / "control-result.json"}"
    showCompilerLogs directory
    check "always-accepting control completes with intact executor evidence"
      (execution.state == .completed && execution.problems.isEmpty && execution.retentionErrors.isEmpty)
    check "always-accepting control is FAIL with both obligations and complete evidence"
      (assessment.status == .fail && assessment.problems.isEmpty &&
       assessment.rows.size == 2 && assessment.rows.map (·.job.name) == control.jobs.map (·.name) &&
       assessment.rows.all fun row => row.evidenceComplete && row.job.expected == .valid &&
        row.job.propertyId == propertyId && row.job.binding.isNone &&
        row.job.txModelId == some modelId)
    for row in assessment.rows do
      if row.job.role == .applicability then
        check "always-accepting control has a Valid/PASS applicability witness"
          (row.observed == some .valid && row.status == .pass && row.job.applicability.isNone)
      else
        check "always-accepting control falsifies the supported unbounded-range rejection claim"
          (row.observed == some .falsified && row.status == .fail &&
           row.job.applicability == some {
             moduleName := job.moduleName, name := job.name ++ "_applies" })
    check "control execution and assessment retain no official property definition"
      (assessment.propertyDefinition.isNone && execution.propertyDefinition.isNone)
    for source in control.modules do
      let path := directory / (source.name.replace "." "/" ++ ".lean")
      check "control retains its exact synthetic sources and compiler logs"
        ((← IO.FS.readFile path) == source.source &&
         (← (path.withExtension "stdout.log").pathExists) &&
         (← (path.withExtension "stderr.log").pathExists))
    let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
    let jobs ← IO.ofExcept do (← manifest.getObjVal? "jobs").getArr?
    check "retained control manifest has two test-only observations and no official binding"
      ((manifest.getObjVal? "target").toOption == some (.str control.targetName) &&
       (manifest.getObjVal? "propertyDefinition").toOption == some .null && jobs.size == 2 &&
       jobs.all fun job =>
        (job.getObjVal? "property").toOption == some (.str propertyId) &&
        (job.getObjVal? "combinedCheck").toOption == some .null &&
        (job.getObjVal? "transactionModel").toOption == some .null)
    for row in assessment.rows do
      let matching := jobs.filter fun retained =>
        (retained.getObjVal? "name").toOption == some (.str row.job.name)
      let observed := if row.job.role == .applicability then "valid" else "falsified"
      let support := row.job.applicability.map (fun reference => Json.mkObj [
        ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null
      check "control manifest retains exact observations, statements, models, and support links"
        (matching.size == 1 && matching.all fun retained =>
          (retained.getObjVal? "statement").toOption == some (.str row.job.statement) &&
          (retained.getObjVal? "txModelId").toOption == some (.str modelId) &&
          (retained.getObjVal? "role").toOption == some (.str row.job.role.label) &&
          (retained.getObjVal? "applicability").toOption == some support &&
          (retained.getObjVal? "observed").toOption == some (.str observed))
  check "Claim and Cancel controls retain separate evidence"
    (directories.size == 2 && directories[0]! != directories[1]!)
  IO.println "UP013 always-accepting controls passed (the property failures are intentional)."

end Workflow.Tests.UP013.NegativeControl

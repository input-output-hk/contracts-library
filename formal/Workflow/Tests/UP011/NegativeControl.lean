import Formal.Properties.Universal.UP011.Tests.Standalone.Fixture
import Workflow.Assessor
import Workflow.Executor
import Workflow.Tests.Support
import Workflow.Tests.UP011.Fixture

namespace Workflow.Tests.UP011.NegativeControl

open Lean Workflow Workflow.Tests.Support

private def propertyId := "UP-011-address-ignoring-control"

private def blueprint :=
  "Formal/Properties/Universal/UP011/Tests/Standalone/Inputs/control.json"

private def controlCode := _root_.Tests.UP011.Fixture.compiledCode

private def note :=
  "TEST ONLY: replace the admitted program with the frozen compiled address-ignoring fixture; retain the native UP-011 Claim statement, all five premises, applicability obligation, payment-credential mutation, TxM-007 context, argument encoding, and 1,000,000 CEK-step bound."

private def replaceOnce (source before after : String) : Except String String := do
  unless (source.splitOn before).length == 2 do
    throw "address-ignoring control: expected exactly one generated declaration"
  return source.replace before after

/-- Replace only the program and its computed hash in an admitted native plan. -/
def plan (original : GenerationPlan) (target : TargetDescription) : Except String GenerationPlan := do
  let some types := original.modules[0]? | throw "address-ignoring control: missing Types module"
  let some job := original.jobs[0]? | throw "address-ignoring control: missing property obligation"
  let some support := original.jobs[1]? | throw "address-ignoring control: missing applicability obligation"
  unless types.name.endsWith ".Types" && original.modules.size == 3 && original.jobs.size == 2 &&
      job.txModelId == some "TxM-007" && support.txModelId == some "TxM-007" &&
      job.role == .property && support.role == .applicability &&
      job.applicability == some { moduleName := support.moduleName, name := support.name } &&
      support.applicability.isNone do
    throw "address-ignoring control: unexpected native Claim plan layout"
  let source ← replaceOnce types.source
    s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr target.compiledCode.toLower}"
    s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr controlCode}"
  let originalHash ← Preparation.Program.scriptHashHex target.compiledCode.toLower
  let controlHash ← Preparation.Program.scriptHashHex controlCode
  unless controlHash == _root_.Tests.UP011.Fixture.scriptHashHex do
    throw "address-ignoring control: compiled fixture hash mismatch"
  let source ← replaceOnce source
    s!"def scriptHashHex : String := {reprStr originalHash}"
    s!"def scriptHashHex : String := {reprStr controlHash}"
  return { original with
    targetName := s!"{propertyId}.TxM-007"
    modules := original.modules.set! 0 { types with source := s!"-- {note}\n{source}" }
    jobs := original.jobs.map fun job => { job with propertyId, binding := none }
    notes := original.notes.push note
    bindingsRequired := false
    propertyDefinition := none }

private def controlInput : IO InputResult := do
  _root_.Tests.UP011.Fixture.checkSource
  let input ← IO.ofExcept ((← Input.read blueprint "ignore_address.ignore_address").mapError toString)
  check "compiled address-ignoring control executes the exact retained blueprint bytes"
    (input.target.compiledCode == controlCode)
  return input

private def prepared : IO (GenerationPlan × GenerationPlan) := do
  let catalogue ← Fixture.catalogue
  let input ← Fixture.input
  let some id := Fixture.selection[0]? | throw (IO.userError "address-ignoring control: missing Claim selection")
  let configured ← IO.ofExcept (catalogue.loadCheck id)
  let original ← IO.ofExcept ((Generator.generateOne configured input.target "Generated").mapError toString)
  return (original, ← IO.ofExcept (plan original input.target))

def unit : IO Unit := do
  let input ← Fixture.input
  let _ ← controlInput
  let originalHash ← IO.ofExcept (Preparation.Program.scriptHashHex input.target.compiledCode.toLower)
  let controlHash ← IO.ofExcept (Preparation.Program.scriptHashHex controlCode)
  let (original, control) ← prepared
  check "address-ignoring control preserves both native obligations" (control.jobs.size == 2)
  for index in [:original.jobs.size] do
    let some before := original.jobs[index]? | throw (IO.userError "missing native obligation")
    let some after := control.jobs[index]? | throw (IO.userError "missing control obligation")
    check "address-ignoring control preserves each claim, model, role, support link, and scope"
      (after.name == before.name && after.moduleName == before.moduleName &&
       after.statement == before.statement && after.scope == before.scope &&
       after.txModelId == before.txModelId && after.txModelId == some "TxM-007" &&
       after.expected == before.expected && after.expected == .valid &&
       after.role == before.role && after.applicability == before.applicability &&
       after.propertyId == propertyId && after.binding.isNone)
  check "address-ignoring control preserves native contexts and both proof declarations"
    (control.modules[1]?.map (·.source) == original.modules[1]?.map (·.source) &&
     control.modules[2]?.map (·.source) == original.modules[2]?.map (·.source))
  check "address-ignoring control clears official attribution and uses a test-only identity"
    (control.targetName == s!"{propertyId}.TxM-007" && control.propertyDefinition.isNone &&
     !control.bindingsRequired && control.validateBindings.isOk && control.notes.contains note)
  let some types := control.modules[0]? | throw (IO.userError "missing control Types module")
  let source := types.source
  check "address-ignoring source embeds the compiled control and its computed hash"
    ((source.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr controlCode}").length == 2 &&
     (source.splitOn s!"def scriptHashHex : String := {reprStr controlHash}").length == 2 &&
     (source.splitOn input.target.compiledCode.toLower).length == 1 &&
     (source.splitOn originalHash).length == 1)
  check "address-ignoring control retains context encoding and explicit rejection semantics"
    ((source.splitOn "def args (ctx : ScriptContext) : List Term := [toTerm ctx]").length == 2 &&
     (source.splitOn "cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)").length == 2 &&
     (source.splitOn "Formal.Support.rejectedWithin program (args ctx) fuel").length == 2)
  IO.println "UP011 compiled address-ignoring control preparation checks passed."

def run : IO Unit := do
  let reference ← Fixture.input
  let input ← controlInput
  let (_, control) ← prepared
  let some job := control.jobs[0]? | throw (IO.userError "missing control obligation")
  startCase "UP011: compiled address-ignoring control for Claim"
    "FAIL; Falsified property obligation and Valid applicability obligation"
    "native plan -> compiled address-ignoring fixture -> Executor.run -> Assessor.assessPlan" 300000
  let execution ← IO.ofExcept (← Executor.run control {
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    outputRoot := some "output"
    budgetMs := 300000 })
  let assessment := Assessor.assessPlan control execution
  let some directory := execution.directory
    | throw (IO.userError "address-ignoring control: missing evidence directory")
  IO.FS.writeFile (directory / "input.json") input.sourceText
  IO.FS.writeFile (directory / "reference-input.json") reference.sourceText
  let result := Json.mkObj [
    ("control", .str propertyId), ("scope", .str note),
    ("target", .str control.targetName),
    ("program", .str "frozen compiled address-ignoring fixture"),
    ("script_hash", .str _root_.Tests.UP011.Fixture.scriptHashHex),
    ("input", .str "input.json"),
    ("input_role", .str "compiled control blueprint; its program was executed"),
    ("reference_input", .str "reference-input.json"),
    ("reference_input_role", .str "reference only; the original vesting program was replaced"),
    ("status", .str assessment.status.label),
    ("propertyDefinition", .null),
    ("obligations", .arr (assessment.rows.map fun row => Json.mkObj [
      ("name", .str row.job.name), ("tx_model", .str "TxM-007"),
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
  check "address-ignoring control retains the executed input and original reference separately"
    ((← IO.FS.readFile (directory / "input.json")) == input.sourceText &&
     (← IO.FS.readFile (directory / "reference-input.json")) == reference.sourceText &&
     input.sourceText != reference.sourceText &&
     (← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "control-result.json")))) == result)
  IO.println s!"ControlResult: {directory / "control-result.json"}"
  showCompilerLogs directory
  check "address-ignoring control completes with intact executor evidence"
    (execution.state == .completed && execution.problems.isEmpty && execution.retentionErrors.isEmpty)
  check "address-ignoring control is FAIL with both obligations and complete evidence"
    (assessment.status == .fail && assessment.problems.isEmpty &&
     assessment.rows.size == 2 && assessment.rows.map (·.job.name) == control.jobs.map (·.name) &&
     assessment.rows.all fun row => row.evidenceComplete && row.job.expected == .valid &&
      row.job.propertyId == propertyId && row.job.binding.isNone &&
      row.job.txModelId == some "TxM-007")
  for row in assessment.rows do
    if row.job.role == .applicability then
      check "address-ignoring control has a Valid/PASS applicability witness for all five premises"
        (row.observed == some .valid && row.status == .pass && row.job.applicability.isNone)
    else
      check "address-ignoring control falsifies continuation-payment-credential rejection"
        (row.observed == some .falsified && row.status == .fail &&
         row.job.applicability == some {
           moduleName := job.moduleName, name := job.name ++ "_applies" })
  check "control execution and assessment retain no official property definition"
    (assessment.propertyDefinition.isNone && execution.propertyDefinition.isNone)
  for source in control.modules do
    let path := directory / (source.name.replace "." "/" ++ ".lean")
    check "control retains its exact generated sources and compiler logs"
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
        (retained.getObjVal? "txModelId").toOption == some (.str "TxM-007") &&
        (retained.getObjVal? "role").toOption == some (.str row.job.role.label) &&
        (retained.getObjVal? "applicability").toOption == some support &&
        (retained.getObjVal? "observed").toOption == some (.str observed))
  IO.println "UP011 compiled address-ignoring control passed (the property failure is intentional)."

end Workflow.Tests.UP011.NegativeControl

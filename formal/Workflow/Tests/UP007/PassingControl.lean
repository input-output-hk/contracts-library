import Formal.Properties.Universal.UP007.Tests.Standalone.Control
import Workflow.Assessor
import Workflow.Executor
import Workflow.Tests.Support
import Workflow.Tests.UP007.Fixture

namespace Workflow.Tests.UP007.PassingControl

open Lean Workflow Workflow.Tests.Support

private def propertyId := "UP-007-stake-enforcing-control"

private def blueprint :=
  "Formal/Properties/Universal/UP007/Tests/Standalone/Inputs/control.json"

private def note :=
  "TEST ONLY: replace the admitted program with the frozen compiled stake_control fixture, which requires the first output's payment and staking credentials to equal those of the spent input. Retain the native UP-007 Claim statement, all five premises, applicability obligation, mutation of only the first continuation's Option StakingCredential, TxM-007 context, argument encoding, and 1,000,000 CEK-step bound."

private def replaceOnce (source before after : String) : Except String String := do
  unless (source.splitOn before).length == 2 do
    throw "stake-enforcing control: expected exactly one generated declaration"
  return source.replace before after

/-- Replace only the program and its computed hash in an admitted native plan. -/
def plan (original : GenerationPlan) (target : TargetDescription) (controlCode : String) :
    Except String GenerationPlan := do
  let some types := original.modules[0]? | throw "stake-enforcing control: missing Types module"
  let some job := original.jobs[0]? | throw "stake-enforcing control: missing property obligation"
  let some support := original.jobs[1]? | throw "stake-enforcing control: missing applicability obligation"
  unless types.name.endsWith ".Types" && original.modules.size == 3 && original.jobs.size == 2 &&
      job.txModelId == some "TxM-007" && support.txModelId == some "TxM-007" &&
      job.role == .property && support.role == .applicability &&
      job.applicability == some { moduleName := support.moduleName, name := support.name } &&
      support.applicability.isNone do
    throw "stake-enforcing control: unexpected native Claim plan layout"
  let source ← replaceOnce types.source
    s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr target.compiledCode.toLower}"
    s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr controlCode}"
  let originalHash ← Preparation.Program.scriptHashHex target.compiledCode.toLower
  let controlHash ← Preparation.Program.scriptHashHex controlCode
  unless controlHash == Formal.Tests.UP007.controlScriptHashHex do
    throw "stake-enforcing control: compiled fixture hash mismatch"
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
  let input ← IO.ofExcept ((← Input.read blueprint "stake_control.stake_control").mapError toString)
  let decoded ← IO.ofExcept
    (PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex?
      input.target.compiledCode)
  let computedHash ← IO.ofExcept (Preparation.Program.scriptHashHex input.target.compiledCode.toLower)
  check "compiled stake-enforcing input decodes to the frozen standalone control program"
    (reprStr decoded == reprStr Formal.Tests.UP007.controlProgram)
  let compiler := input.target.compiler.getD .null
  check "compiled stake-enforcing control retains its compiler, language, and handler identity"
    (input.target.plutusVersion == "v3" &&
     (input.target.parameters.getD #[]).isEmpty &&
     (compiler.getObjVal? "name").toOption == some (.str "Aiken") &&
     (compiler.getObjVal? "version").toOption == some (.str "v1.1.21+42babe5") &&
     input.target.handlers.map (·.name) ==
       #["stake_control.stake_control.spend", "stake_control.stake_control.else"])
  check "compiled stake-enforcing control independently recomputes the recorded script hash"
    (computedHash == Formal.Tests.UP007.controlScriptHashHex &&
     input.target.handlers.all (·.declaredHash == some computedHash))
  return input

private def prepared (controlCode : String) : IO (GenerationPlan × GenerationPlan) := do
  let catalogue ← Fixture.catalogue
  let input ← Fixture.input
  let some id := Fixture.selection[0]? | throw (IO.userError "stake-enforcing control: missing Claim selection")
  let configured ← IO.ofExcept (catalogue.loadCheck id)
  let original ← IO.ofExcept ((Generator.generateOne configured input.target "Generated").mapError toString)
  return (original, ← IO.ofExcept (plan original input.target controlCode))

def unit : IO Unit := do
  let input ← Fixture.input
  let frozen ← controlInput
  let controlCode := frozen.target.compiledCode.toLower
  let originalHash ← IO.ofExcept (Preparation.Program.scriptHashHex input.target.compiledCode.toLower)
  let controlHash ← IO.ofExcept (Preparation.Program.scriptHashHex controlCode)
  let (original, control) ← prepared controlCode
  check "stake-enforcing control preserves both native obligations" (control.jobs.size == 2)
  for index in [:original.jobs.size] do
    let some before := original.jobs[index]? | throw (IO.userError "missing native obligation")
    let some after := control.jobs[index]? | throw (IO.userError "missing control obligation")
    check "stake-enforcing control preserves each claim, model, role, support link, and scope"
      (after.name == before.name && after.moduleName == before.moduleName &&
       after.statement == before.statement && after.scope == before.scope &&
       after.txModelId == before.txModelId && after.txModelId == some "TxM-007" &&
       after.expected == before.expected && after.expected == .valid &&
       after.role == before.role && after.applicability == before.applicability &&
       after.propertyId == propertyId && after.binding.isNone)
  check "stake-enforcing control preserves native contexts and both proof declarations"
    (control.modules[1]?.map (·.source) == original.modules[1]?.map (·.source) &&
     control.modules[2]?.map (·.source) == original.modules[2]?.map (·.source))
  check "stake-enforcing control clears official attribution and uses a test-only identity"
    (control.targetName == s!"{propertyId}.TxM-007" && control.propertyDefinition.isNone &&
     !control.bindingsRequired && control.validateBindings.isOk && control.notes.contains note)
  let some types := control.modules[0]? | throw (IO.userError "missing control Types module")
  let source := types.source
  check "stake-enforcing source embeds the compiled control and its computed hash"
    ((source.splitOn s!"def program : Program := singleCborEncodedScriptFromHexM {reprStr controlCode}").length == 2 &&
     (source.splitOn s!"def scriptHashHex : String := {reprStr controlHash}").length == 2 &&
     (source.splitOn input.target.compiledCode.toLower).length == 1 &&
     (source.splitOn originalHash).length == 1)
  check "stake-enforcing control retains context encoding and explicit rejection semantics"
    ((source.splitOn "def args (ctx : ScriptContext) : List Term := [toTerm ctx]").length == 2 &&
     (source.splitOn "cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)").length == 2 &&
     (source.splitOn "Formal.Support.rejectedWithin program (args ctx) fuel").length == 2)
  IO.println "UP007 compiled stake-enforcing control preparation checks passed."

def run : IO Unit := do
  let reference ← Fixture.input
  let input ← controlInput
  let computedHash ← IO.ofExcept (Preparation.Program.scriptHashHex input.target.compiledCode.toLower)
  let (_, control) ← prepared input.target.compiledCode.toLower
  let some job := control.jobs[0]? | throw (IO.userError "missing control obligation")
  startCase "UP007: compiled stake-enforcing control for Claim"
    "PASS; Valid property obligation and Valid applicability obligation"
    "native plan -> compiled stake-enforcing fixture -> Executor.run -> Assessor.assessPlan" 300000
  let execution ← IO.ofExcept (← Executor.run control {
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    outputRoot := some "output"
    budgetMs := 300000 })
  let assessment := Assessor.assessPlan control execution
  let some directory := execution.directory
    | throw (IO.userError "stake-enforcing control: missing evidence directory")
  IO.FS.writeFile (directory / "input.json") input.sourceText
  IO.FS.writeFile (directory / "reference-input.json") reference.sourceText
  let result := Json.mkObj [
    ("control", .str propertyId), ("scope", .str note),
    ("target", .str control.targetName),
    ("program", .str "frozen compiled stake-enforcing fixture"),
    ("compiled_code", .str input.target.compiledCode),
    ("script_hash", .str computedHash),
    ("input", .str "input.json"),
    ("input_role", .str "compiled control blueprint; its program was executed"),
    ("reference_input", .str "reference-input.json"),
    ("reference_input_role", .str "reference only; the original vesting program was replaced"),
    ("status", .str assessment.status.label),
    ("propertyDefinition", .null),
    ("obligations", .arr (assessment.rows.map fun row => Json.mkObj [
      ("name", .str row.job.name), ("module", .str row.job.moduleName),
      ("scope", .str row.job.scope), ("tx_model", .str "TxM-007"),
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
  check "stake-enforcing control retains the executed input and original reference separately"
    ((← IO.FS.readFile (directory / "input.json")) == input.sourceText &&
     (← IO.FS.readFile (directory / "reference-input.json")) == reference.sourceText &&
     input.sourceText != reference.sourceText &&
     (← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "control-result.json")))) == result)
  IO.println s!"ControlResult: {directory / "control-result.json"}"
  showCompilerLogs directory
  check "stake-enforcing control completes with intact executor evidence"
    (execution.state == .completed && execution.problems.isEmpty && execution.retentionErrors.isEmpty)
  check "stake-enforcing control is PASS with both obligations and complete evidence"
    (assessment.status == .pass && assessment.problems.isEmpty &&
     assessment.rows.size == 2 && assessment.rows.map (·.job.name) == control.jobs.map (·.name) &&
     assessment.rows.all fun row => row.evidenceComplete && row.job.expected == .valid &&
      row.job.propertyId == propertyId && row.job.binding.isNone &&
      row.job.txModelId == some "TxM-007")
  for row in assessment.rows do
    if row.job.role == .applicability then
      check "stake-enforcing control has a Valid/PASS applicability witness for all five premises"
        (row.observed == some .valid && row.status == .pass && row.job.applicability.isNone)
    else
      check "stake-enforcing control establishes bounded continuation-stake rejection"
        (row.observed == some .valid && row.status == .pass &&
         row.job.applicability == some {
           moduleName := job.moduleName, name := job.name ++ "_applies" })
  check "control execution and assessment retain no official property definition"
    (assessment.propertyDefinition.isNone && execution.propertyDefinition.isNone)
  let manifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "execution.json")))
  let modules ← IO.ofExcept do (← manifest.getObjVal? "modules").getArr?
  check "control execution retains exactly the three native generated module names"
    (modules.size == 3 && control.modules.map (·.name) ==
      #["Generated.Types", "Generated.Tx", "Generated.Checks"])
  for source in control.modules do
    let path := directory / (source.name.replace "." "/" ++ ".lean")
    check "control retains its exact generated sources and compiler logs"
      ((← IO.FS.readFile path) == source.source &&
       (← (path.withExtension "stdout.log").pathExists) &&
       (← (path.withExtension "stderr.log").pathExists))
    check "control execution links each generated module to its retained source"
      ((modules.filter fun entry =>
        (entry.getObjVal? "path").toOption == some (.str path.toString)).size == 1)
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
    let support := row.job.applicability.map (fun reference => Json.mkObj [
      ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null
    check "control manifest retains exact observations, statements, models, and support links"
      (matching.size == 1 && matching.all fun retained =>
        (retained.getObjVal? "module").toOption == some (.str row.job.moduleName) &&
        (retained.getObjVal? "statement").toOption == some (.str row.job.statement) &&
        (retained.getObjVal? "scope").toOption == some (.str row.job.scope) &&
        (retained.getObjVal? "txModelId").toOption == some (.str "TxM-007") &&
        (retained.getObjVal? "role").toOption == some (.str row.job.role.label) &&
        (retained.getObjVal? "applicability").toOption == some support &&
        (retained.getObjVal? "expected").toOption == some (.str "valid") &&
        (retained.getObjVal? "evidenceComplete").toOption == some (.bool true) &&
        (retained.getObjVal? "observed").toOption == some (.str "valid"))
  IO.println "UP007 compiled stake-enforcing control passed with two Valid obligations."

end Workflow.Tests.UP007.PassingControl

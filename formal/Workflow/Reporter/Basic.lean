import Workflow.Assessor.Basic

namespace Workflow.Reporter

open Lean

abbrev Status := Assessor.Status
abbrev Row := Assessor.Row

namespace Status
export Assessor.Status (pass fail inconclusive)
def label (status : Status) : String := Assessor.Status.label status
end Status

structure Report where
  target : String
  status : Status
  rows : Array Row := #[]
  problems : Array String := #[]
  notes : Array String := #[]
  evidenceDirectory : Option System.FilePath := none
  propertyDefinition : Option PropertyDefinition := none

def Report.exitCode (report : Report) : UInt32 :=
  match report.status with
  | .pass => 0
  | .fail => 1
  | .inconclusive => 2

/-- Retain the existing report interface while assessment belongs to Assessor. -/
def build (plan : GenerationPlan) (execution : Executor.Result) : Report :=
  let assessed := Assessor.assessPlan plan execution
  { target := assessed.target, status := assessed.status, rows := assessed.rows,
    problems := assessed.problems, notes := assessed.notes,
    evidenceDirectory := assessed.evidenceDirectory, propertyDefinition := assessed.propertyDefinition }

def failure (target message : String) (propertyDefinition : Option PropertyDefinition := none) : Report :=
  { target, status := .inconclusive, problems := #[message], propertyDefinition }

private def expectedText : ExpectedResult → String
  | .valid => "valid"
  | .falsified => "falsified"

private def observedText : Executor.ObservedResult → String
  | .valid => "valid"
  | .falsified => "falsified"
  | .inconclusive => "inconclusive"

def Report.toJson (report : Report) : Json :=
  let rows := report.rows.map fun row => Json.mkObj [
    ("property", .str row.job.propertyId), ("name", .str row.job.name),
    ("module", .str row.job.moduleName), ("scope", .str row.job.scope),
    ("statement", .str row.job.statement),
    ("role", .str row.job.role.label),
    ("txModelId", row.job.txModelId.map Json.str |>.getD .null),
    ("transactionModel", row.job.binding.map (fun binding => binding.txModel.toJson) |>.getD .null),
    ("combinedCheck", row.job.binding.map (fun binding => binding.combinedCheck.toJson) |>.getD .null),
    ("applicability", row.job.applicability.map (fun reference => Json.mkObj [
      ("module", .str reference.moduleName), ("name", .str reference.name)]) |>.getD .null),
    ("evidenceComplete", .bool row.evidenceComplete),
    ("expected", .str (expectedText row.job.expected)),
    ("observed", row.observed.map (fun value => Json.str (observedText value)) |>.getD .null),
    ("status", .str row.status.label), ("issues", Lean.toJson row.issues)]
  Json.mkObj [
    ("schemaVersion", Lean.toJson (1 : Nat)), ("target", .str report.target),
    ("status", .str report.status.label), ("exitCode", Lean.toJson report.exitCode.toNat),
    ("propertyDefinition", report.propertyDefinition.map (·.toJson) |>.getD .null),
    ("checks", .arr rows), ("problems", Lean.toJson report.problems), ("notes", Lean.toJson report.notes),
    ("evidenceDirectory", report.evidenceDirectory.map (fun path => Json.str path.toString) |>.getD .null)]

private def oneLine (text : String) : String :=
  text.replace "\r" "\\r" |>.replace "\n" "\\n" |>.replace "\t" "\\t"

private def definitionLabel : String → String
  | "schema_version" => "Metadata format"
  | "identity.id" => "Property"
  | "identity.definition_version" => "Definition version"
  | "identity.title" => "Title"
  | "identity.category" => "Category"
  | "explanation.summary" => "Description"
  | "explanation.claim" => "Claim"
  | "explanation.purpose" => "Purpose"
  | "scope.relevance_conditions" => "Relevance conditions"
  | "scope.preconditions" => "Definition premises"
  | "scope.limitations" => "Definition limitations"
  | "formalization.primary" => "Formal definition"
  | "formalization.theorems" => "Static theorem references"
  | label =>
    if label.startsWith "references[" then
      if label.endsWith ".label" then "Reference label" else "Reference"
    else label

private def modelLabel : String → String
  | "id" => "Model"
  | "title" => "Model title"
  | "plutus_version" => "Plutus version"
  | "description" => "Model description"
  | label => label

def Report.text (report : Report) : String := Id.run do
  let mut lines := #[s!"Target: {oneLine report.target}"]
  if let some definition := report.propertyDefinition then
    for (label, value) in definition.textFields do
      lines := lines.push s!"{oneLine (definitionLabel label)}: {oneLine value}"
  for row in report.rows do
    lines := lines.push s!"{row.status.label} {oneLine row.job.propertyId} {oneLine row.job.name}"
    if let some binding := row.job.binding then
      for (label, value) in binding.txModel.textFields do
        lines := lines.push s!"  {oneLine (modelLabel label)}: {oneLine value}"
      for (label, value) in binding.combinedCheck.textFields do
        if label == "limitations" then
          lines := lines.push s!"  Combination limitations: {oneLine value}"
    if let some issue := row.issues[0]? then
      lines := lines.push s!"  Reason: {oneLine issue}"
  let count := fun status => (report.rows.filter (·.status == status)).size
  lines := lines.push s!"Summary: {count .pass} PASS, {count .fail} FAIL, {count .inconclusive} INCONCLUSIVE"
  lines := lines.push s!"Overall: {report.status.label} (exit {report.exitCode})"
  if let some problem := report.problems[0]? then
    lines := lines.push s!"Reason: {oneLine problem}"
  if let some directory := report.evidenceDirectory then
    lines := lines.push s!"Evidence: {oneLine directory.toString}"
  return String.intercalate "\n" lines.toList ++ "\n"

/-- Persist only the simple summary; raw diagnostics remain in Executor's evidence. -/
def Report.write (report : Report) (directory : System.FilePath) : IO Unit := do
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "report.json") (report.toJson.pretty ++ "\n")
  IO.FS.writeFile (directory / "report.txt") report.text

end Workflow.Reporter

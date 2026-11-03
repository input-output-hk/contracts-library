import Workflow.Metadata.TxModel

open Lean Workflow

namespace Workflow.Tests.Unit.Metadata.Models

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def rejected {α : Type} (label : String) (result : Except String α)
    (path : String) : IO Unit := do
  match result with
  | .error message => check s!"{label}: precise location" (message.startsWith s!"{path}:")
  | .ok _ => throw (IO.userError s!"FAIL: {label}: malformed metadata was accepted")

private def modelRecord (id : String := "TxM-001") : Json := Json.mkObj [
  ("id", .str id), ("title", .str "Model\ntitle"), ("plutus_version", .str "v3"),
  ("description", .str "Symbolic context with a fixed shape.")]

private def combinedRecord (id : String := "UP-fixture") (version : Int := 1)
    (modelId : String := "TxM-001") : Json := Json.mkObj [
  ("property", Json.mkObj [("id", .str id), ("definition_version", toJson version)]),
  ("tx_model", .str modelId), ("limitations", .arr #[.str "Fixed shape only."])]

private def definitionRecord (id : String := "UP-fixture") (version : Int := 1) : Json :=
  Json.mkObj [("identity", Json.mkObj [("id", .str id), ("definition_version", toJson version)])]

def run : IO Unit := do
  let model ← IO.ofExcept (TransactionModel.parse modelRecord)
  let combination ← IO.ofExcept (CombinedCheck.parse combinedRecord)
  let definition ← IO.ofExcept (PropertyDefinition.parse definitionRecord)
  check "model preserves raw JSON and lookups"
    (model.toJson == modelRecord && model.id? == some "TxM-001" && model.plutusVersion? == some "v3")
  check "combined check preserves raw JSON and lookups"
    (combination.toJson == combinedRecord && combination.propertyId? == some "UP-fixture" &&
     combination.definitionVersion? == some 1 && combination.txModelId? == some "TxM-001")
  check "model text preserves unescaped supplied text"
    (model.textFields.contains ("title", "Model\ntitle"))
  check "combined text preserves reference and limitations"
    (combination.textFields.contains ("property.definition_version", "1") &&
     combination.textFields.contains ("limitations", "[\"Fixed shape only.\"]"))
  let emptyModel ← IO.ofExcept (TransactionModel.parse (Json.mkObj []))
  let emptyCheck ← IO.ofExcept (CombinedCheck.parse (Json.mkObj []))
  check "partial models invent no values"
    (emptyModel.id?.isNone && emptyModel.plutusVersion?.isNone && emptyModel.textFields.isEmpty)
  check "partial combinations invent no values"
    (emptyCheck.propertyId?.isNone && emptyCheck.definitionVersion?.isNone &&
     emptyCheck.txModelId?.isNone && emptyCheck.textFields.isEmpty)
  let emptyValues ← IO.ofExcept (CombinedCheck.parse (Json.mkObj [
    ("property", Json.mkObj []), ("tx_model", .str ""), ("limitations", .arr #[])]))
  check "empty objects, strings, and arrays remain distinguishable from missing fields"
    (emptyValues.textFields == #[("property", "{}"), ("tx_model", ""), ("limitations", "[]")])
  let decimal ← IO.ofExcept (Json.parse "{\"property\":{\"definition_version\":1.0}}")
  check "integral decimal version accepted"
    ((CombinedCheck.parse decimal).toOption.bind (·.definitionVersion?) == some 1)
  let scientific ← IO.ofExcept (Json.parse "{\"property\":{\"definition_version\":1e2}}")
  check "integral scientific version accepted"
    ((CombinedCheck.parse scientific).toOption.bind (·.definitionVersion?) == some 100)
  rejected "huge decimal exponent fraction rejected without large arithmetic"
    (CombinedCheck.parse (Json.mkObj [("property", Json.mkObj [
      ("definition_version", .num ⟨1, 1000000⟩)])])) "$.property.definition_version"
  check "huge decimal exponent zero remains integral"
    ((CombinedCheck.parse (Json.mkObj [("property", Json.mkObj [
      ("definition_version", .num ⟨0, 1000000⟩)])])).toOption.bind (·.definitionVersion?) == some 0)

  for invalid in [.null, .bool false, .num 1, .str "record", .arr #[]] do
    rejected "model object required" (TransactionModel.parse invalid) "$"
    rejected "combination object required" (CombinedCheck.parse invalid) "$"
  for name in ["id", "title", "plutus_version", "description"] do
    check s!"empty model {name} string remains allowed"
      ((TransactionModel.parse (Json.mkObj [(name, .str "")])).isOk)
    for invalid in [.null, .num 1, .arr #[]] do
      rejected s!"model {name} string required"
        (TransactionModel.parse (Json.mkObj [(name, invalid)])) s!"$.{name}"
  for name in ["schema_version", "model_version", "formalization", "references", "limitations", "construction"] do
    rejected s!"removed model field {name} rejected"
      (TransactionModel.parse (Json.mkObj [(name, .arr #[])])) s!"$.{name}"
  for name in ["model", "property_id", "tx_model_id", "schema_version"] do
    rejected s!"unknown combination field {name} rejected"
      (CombinedCheck.parse (Json.mkObj [(name, .str "value")])) s!"$.{name}"
  for invalid in [.null, .str "UP-fixture", .arr #[]] do
    rejected "property reference object required"
      (CombinedCheck.parse (Json.mkObj [("property", invalid)])) "$.property"
  rejected "unknown property reference field rejected"
    (CombinedCheck.parse (Json.mkObj [("property", Json.mkObj [("version", .num 1)])])) "$.property.version"
  for invalid in [.null, .num 1, .arr #[]] do
    rejected "property reference ID string required"
      (CombinedCheck.parse (Json.mkObj [("property", Json.mkObj [("id", invalid)])])) "$.property.id"
    rejected "model reference string required"
      (CombinedCheck.parse (Json.mkObj [("tx_model", invalid)])) "$.tx_model"
  for invalid in [.null, .str "1", .num ⟨15, 1⟩] do
    rejected "property reference version integer required"
      (CombinedCheck.parse (Json.mkObj [("property", Json.mkObj [("definition_version", invalid)])]))
      "$.property.definition_version"
  for invalid in [.null, .str "none", .num 1] do
    rejected "limitation list required"
      (CombinedCheck.parse (Json.mkObj [("limitations", invalid)])) "$.limitations"
  rejected "limitation list entries must be text"
    (CombinedCheck.parse (Json.mkObj [("limitations", .arr #[.str "first", .null])])) "$.limitations[1]"
  check "model list preserves ordering and partial records"
    ((TransactionModel.parseList (.arr #[modelRecord, Json.mkObj []])).toOption == some #[model, emptyModel])
  check "combined list preserves ordering and partial records"
    ((CombinedCheck.parseList (.arr #[combinedRecord, Json.mkObj []])).toOption == some #[combination, emptyCheck])
  check "empty collections remain allowed"
    ((TransactionModel.parseList (.arr #[])).toOption == some #[] &&
     (CombinedCheck.parseList (.arr #[])).toOption == some #[])
  rejected "model collection root" (TransactionModel.parseList modelRecord) "$"
  rejected "combination collection root" (CombinedCheck.parseList combinedRecord) "$"
  rejected "model collection index"
    (TransactionModel.parseList (.arr #[modelRecord, .null])) "$[1]"
  rejected "combination collection index"
    (CombinedCheck.parseList (.arr #[combinedRecord, .null])) "$[1]"

  IO.FS.withTempDir fun directory => do
    let path := directory / "models.json"
    let source := (Json.arr #[modelRecord]).pretty
    IO.FS.writeFile path source
    check "model file round trip" ((← TransactionModel.read path).toOption == some #[model])
    check "model reader leaves source unchanged" ((← IO.FS.readFile path) == source)
    IO.FS.writeFile path (Json.arr #[combinedRecord]).pretty
    check "combination file round trip" ((← CombinedCheck.read path).toOption == some #[combination])
    IO.FS.writeFile path "{"
    rejected "model malformed JSON" (← TransactionModel.read path) s!"{path}: invalid JSON"
    rejected "combination malformed JSON" (← CombinedCheck.read path) s!"{path}: invalid JSON"
    IO.FS.writeFile path "[null]"
    rejected "model malformed file record" (← TransactionModel.read path) s!"{path}: $[0]"
    rejected "combination malformed file record" (← CombinedCheck.read path) s!"{path}: $[0]"
    let missing := directory / "missing.json"
    rejected "model missing file" (← TransactionModel.read missing) missing.toString
    rejected "combination missing file" (← CombinedCheck.read missing) missing.toString

  let binding ← IO.ofExcept (CheckBinding.resolve definition "TxM-001" #[model] #[combination])
  check "binding retains both selected raw records"
    (binding.txModel == model && binding.combinedCheck == combination)
  check "binding validates for its property" ((binding.validate "UP-fixture" definition).isOk)
  check "binding rejects a different job property" (!(binding.validate "UP-other" definition).isOk)
  let otherModel ← IO.ofExcept (TransactionModel.parse (modelRecord "TxM-002"))
  let otherVersion ← IO.ofExcept (CombinedCheck.parse (combinedRecord "UP-fixture" 2))
  let otherProperty ← IO.ofExcept (CombinedCheck.parse (combinedRecord "UP-other"))
  let otherPair ← IO.ofExcept (CombinedCheck.parse (combinedRecord "UP-fixture" 1 "TxM-002"))
  check "resolution selects the exact property/version/model rather than array order"
    ((CheckBinding.resolve definition "TxM-001" #[otherModel, model]
      #[otherVersion, otherProperty, otherPair, combination]).toOption == some binding)
  for models in [#[], #[emptyModel], #[otherModel], #[model, model]] do
    check "missing and ambiguous model records cannot resolve"
      (!(CheckBinding.resolve definition "TxM-001" models #[combination]).isOk)
  for combinations in [#[], #[emptyCheck], #[otherVersion], #[otherProperty], #[otherPair],
      #[combination, combination]] do
    check "missing and ambiguous exact combinations cannot resolve"
      (!(CheckBinding.resolve definition "TxM-001" #[model] combinations).isOk)
  check "mismatched model snapshot cannot validate"
    (!(({ binding with txModel := otherModel }).validate "UP-fixture" definition).isOk)
  for value in [Json.mkObj [], Json.mkObj [("identity", Json.mkObj [("id", .str "UP-fixture")])],
      definitionRecord ""] do
    let incomplete ← IO.ofExcept (PropertyDefinition.parse value)
    check "shape-valid missing runtime property identity cannot bind"
      (!(CheckBinding.resolve incomplete "TxM-001" #[model] #[combination]).isOk)
  check "empty selected model ID cannot bind"
    (!(CheckBinding.resolve definition "" #[model] #[combination]).isOk)
  check "shape-valid missing model identity cannot validate"
    (!(({ binding with txModel := emptyModel }).validate "UP-fixture" definition).isOk)
  IO.println "Model and combined-check metadata checks passed."

end Workflow.Tests.Unit.Metadata.Models

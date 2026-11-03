import Workflow.Metadata.Property
import Candidates.Catalogue
import Workflow.Tests.Unit.Metadata.Models
import Workflow.Tests.Unit.Metadata.Bindings

open Lean Workflow

namespace Workflow.Tests.Unit.Metadata

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def accepted (value : Json) : IO PropertyDefinition :=
  IO.ofExcept (PropertyDefinition.parse value)

private def rejected (label : String) (value : Json) (path : String) : IO Unit := do
  match PropertyDefinition.parse value with
  | .ok _ => throw (IO.userError s!"FAIL: {label}: malformed metadata was accepted")
  | .error message => check s!"{label}: precise location" (message.startsWith s!"{path}:")

private def record : Json := Json.mkObj [
  ("schema_version", toJson (2 : Int)),
  ("identity", Json.mkObj [("id", .str "UP-fixture"), ("definition_version", toJson (1 : Int)),
    ("title", .str "Fixture\nproperty"), ("category", .str "test")]),
  ("explanation", Json.mkObj [("summary", .str "Summary"), ("claim", .str "Claim"),
    ("purpose", .str "Purpose")]),
  ("scope", Json.mkObj [("relevance_conditions", .arr #[.str "Relevant"]),
    ("preconditions", .arr #[.str "Precondition"]), ("limitations", .arr #[.str "Limitation"])]),
  ("formalization", Json.mkObj [("primary", .str "Fixture.statement"),
    ("theorems", .arr #[.str "Fixture.theorem", .str "Fixture.lemma"])]),
  ("references", .arr #[Json.mkObj [("label", .str "Source"),
    ("target", .str "https://example.invalid/not-fetched")],
    Json.mkObj [("target", .str "Fixture.lean")]])]

private def catalogueRecord (id : String := "UP-001") (version : Int := 1)
    (primary : Option String := none) : IO PropertyDefinition :=
  accepted (Json.mkObj ([("identity", Json.mkObj [("id", .str id),
    ("definition_version", toJson version)])] ++
    primary.toList.map (fun name => ("formalization", Json.mkObj [("primary", .str name)]))))

def run : IO Unit := do
  Models.run
  Bindings.run
  let definition ← accepted record
  check "complete record keeps its raw snapshot" (definition.toJson == record)
  check "equal snapshots compare equal" (definition == (← accepted record))
  check "identity lookups" (definition.id? == some "UP-fixture" && definition.version? == some 1)
  check "primary lookup" (definition.primary? == some "Fixture.statement")
  let fields := definition.textFields
  check "text keeps exact supplied strings" (fields.contains ("identity.title", "Fixture\nproperty"))
  check "text keeps theorem list" (fields.contains
    ("formalization.theorems", "[\"Fixture.theorem\",\"Fixture.lemma\"]"))
  check "reference targets are informational text" (fields.contains
    ("references[0].target", "https://example.invalid/not-fetched") &&
    fields.contains ("references[1].target", "Fixture.lean"))
  check "missing reference label is not invented"
    (!(fields.any fun (name, _) => name == "references[1].label"))

  let incomplete ← accepted (Json.mkObj [])
  check "empty partial record is accepted without invented values"
    (incomplete.id?.isNone && incomplete.version?.isNone && incomplete.primary?.isNone && incomplete.textFields.isEmpty)
  let emptyGroups ← accepted (Json.mkObj [("identity", Json.mkObj []),
    ("explanation", Json.mkObj []), ("scope", Json.mkObj []), ("formalization", Json.mkObj [])])
  check "present empty groups remain present" (emptyGroups.textFields.contains ("identity", "{}"))
  let emptyLists ← accepted (Json.mkObj [
    ("scope", Json.mkObj [("relevance_conditions", .arr #[]), ("preconditions", .arr #[]),
      ("limitations", .arr #[])]),
    ("formalization", Json.mkObj [("theorems", .arr #[])]), ("references", .arr #[])])
  check "empty lists are preserved" (emptyLists.textFields.size == 5 &&
    emptyLists.textFields.all (fun (_, text) => text == "[]"))
  let emptyStrings ← accepted (Json.mkObj [("identity", Json.mkObj [("id", .str ""),
    ("title", .str ""), ("category", .str ""), ("definition_version", toJson (-1 : Int))]),
    ("schema_version", toJson (0 : Int))])
  check "no minimum length or version policy is imposed"
    (emptyStrings.id? == some "" && emptyStrings.version? == some (-1))
  let decimal ← IO.ofExcept (Json.parse "{\"schema_version\":1e2,\"identity\":{\"definition_version\":1.0}}")
  check "integral scientific and decimal numbers are integers" ((← accepted decimal).version? == some 1)
  rejected "tiny fractional version is rejected without a huge decimal division"
    (Json.mkObj [("schema_version", .num ⟨1, 1000000⟩)]) "$.schema_version"
  check "zero remains integral with a large decimal exponent"
    ((PropertyDefinition.parse (Json.mkObj [("schema_version", .num ⟨0, 1000000⟩)])).isOk)
  let partialReferences ← accepted (Json.mkObj [("references", .arr #[Json.mkObj []])])
  check "partial reference object is accepted"
    (partialReferences.textFields == #[("references[0]", "{}")])

  for invalid in [.null, .bool false, .str "metadata", .arr #[], .num 1] do
    rejected "record must be an object" invalid "$"
  rejected "unknown top-level field" (Json.mkObj [("unknown", .str "value")]) "$.unknown"
  for name in ["identity", "explanation", "scope", "formalization"] do
    for invalid in [.null, .str "group", .arr #[]] do
      rejected s!"{name} requires an object" (Json.mkObj [(name, invalid)]) s!"$.{name}"
    rejected s!"{name} is closed" (Json.mkObj [(name, Json.mkObj [("unknown", .str "value")])])
      s!"$.{name}.unknown"
  for invalid in [.null, .str "2", .bool true, .num ⟨15, 1⟩] do
    rejected "schema version requires an integer" (Json.mkObj [("schema_version", invalid)]) "$.schema_version"
    rejected "definition version requires an integer"
      (Json.mkObj [("identity", Json.mkObj [("definition_version", invalid)])]) "$.identity.definition_version"
  for (group, names) in [
      ("identity", ["id", "title", "category"]),
      ("explanation", ["summary", "claim", "purpose"]),
      ("formalization", ["primary"])] do
    for name in names do
      for invalid in [.null, .num 1, .arr #[]] do
        rejected s!"{group}.{name} requires a string"
          (Json.mkObj [(group, Json.mkObj [(name, invalid)])]) s!"$.{group}.{name}"
  for (group, names) in [
      ("scope", ["relevance_conditions", "preconditions", "limitations"]),
      ("formalization", ["theorems"])] do
    for name in names do
      for invalid in [.null, .str "list", .bool false] do
        rejected s!"{group}.{name} requires an array"
          (Json.mkObj [(group, Json.mkObj [(name, invalid)])]) s!"$.{group}.{name}"
      rejected s!"{group}.{name} requires string items"
        (Json.mkObj [(group, Json.mkObj [(name, .arr #[.str "first", .null])])]) s!"$.{group}.{name}[1]"
  for invalid in [.null, .str "references", Json.mkObj []] do
    rejected "references requires an array" (Json.mkObj [("references", invalid)]) "$.references"
  rejected "reference items require objects" (Json.mkObj [("references", .arr #[.null])]) "$.references[0]"
  rejected "reference objects are closed"
    (Json.mkObj [("references", .arr #[Json.mkObj [("unknown", .str "value")]])]) "$.references[0].unknown"
  for name in ["label", "target"] do
    for invalid in [.null, .num 1, .arr #[]] do
      rejected s!"reference {name} requires a string"
        (Json.mkObj [("references", .arr #[Json.mkObj [(name, invalid)]])]) s!"$.references[0].{name}"

  check "empty collection is accepted" ((PropertyDefinition.parseList (.arr #[])).toOption == some #[])
  check "collection preserves order and partial records"
    ((PropertyDefinition.parseList (.arr #[record, Json.mkObj []])).toOption == some #[definition, incomplete])
  match PropertyDefinition.parseList record with
  | .error message => check "collection root location" (message.startsWith "$: expected an array")
  | .ok _ => throw (IO.userError "FAIL: non-array collection was accepted")
  match PropertyDefinition.parseList (.arr #[Json.mkObj [], Json.mkObj [("identity", .null)]]) with
  | .error message => check "collection item location" (message.startsWith "$[1].identity:")
  | .ok _ => throw (IO.userError "FAIL: malformed collection item was accepted")

  IO.FS.withTempDir fun directory => do
    let path := directory / "definitions.json"
    let source := (Json.arr #[record, Json.mkObj []]).pretty
    IO.FS.writeFile path source
    check "file reader returns the full collection"
      ((← PropertyDefinition.read path).toOption == some #[definition, incomplete])
    check "file reader leaves source unchanged" ((← IO.FS.readFile path) == source)
    IO.FS.writeFile path "{"
    match ← PropertyDefinition.read path with
    | .error message => check "malformed file location" (message.startsWith s!"{path}: invalid JSON:")
    | .ok _ => throw (IO.userError "FAIL: malformed file was accepted")
    IO.FS.writeFile path "[null]"
    match ← PropertyDefinition.read path with
    | .error message => check "file validation location" (message.startsWith s!"{path}: $[0]:")
    | .ok _ => throw (IO.userError "FAIL: malformed file record was accepted")
    let missing := directory / "missing.json"
    match ← PropertyDefinition.read missing with
    | .error message => check "file error location" (message.startsWith s!"{missing}:")
    | .ok _ => throw (IO.userError "FAIL: missing file was accepted")
    IO.FS.writeFile path record.pretty
    check "per-property reader preserves one complete record"
      ((← PropertyDefinition.readRecord path).toOption == some definition)
    check "single-record reader does not change the source"
      ((← IO.FS.readFile path) == record.pretty)
    IO.FS.writeFile path "{}"
    check "single-record shape validation keeps partial fields optional"
      ((← PropertyDefinition.readRecord path).toOption == some incomplete)
    IO.FS.writeFile path "[]"
    check "single-record reader rejects a collection wrapper"
      ((← PropertyDefinition.readRecord path).toOption.isNone)
    IO.FS.writeFile path "{"
    check "single-record reader rejects malformed JSON"
      ((← PropertyDefinition.readRecord path).toOption.isNone)
    check "single-record reader reports unavailable files"
      ((← PropertyDefinition.readRecord missing).toOption.isNone)
  let registered ← catalogueRecord
  let selected ← IO.ofExcept (Candidates.Catalogue.withDefinitions none #[registered])
  check "binding accepts a partial descriptive record with the registered identity"
    (selected.id == "UP-001" && selected.propertyDefinition == some registered)
  let alternate ← catalogueRecord "UP-001" 2
  let exact ← IO.ofExcept (Candidates.Catalogue.withDefinitions (some "UP-001") #[alternate, registered])
  check "binding selects its exact definition version rather than the first record"
    (exact.propertyDefinition == some registered)
  for invalidDefinitions in [#[], #[incomplete], #[alternate], #[registered, registered],
      #[(← catalogueRecord "UP-001" 1 (some "Other.unregistered"))]] do
    check "missing, duplicate, mismatched, or wrong-primary records cannot relabel code"
      ((Candidates.Catalogue.withDefinitions (some "UP-001") invalidDefinitions).toOption.isNone)
  check "metadata cannot register a new executable provider"
    ((Candidates.Catalogue.withDefinitions (some "UP-unknown") #[(← catalogueRecord "UP-unknown")]).toOption.isNone)
  for (id, primary) in [("UP-001", "Formal.Properties.Universal.UP001.statement"),
      ("UP-012", "Formal.Properties.Universal.UP012.statement"),
      ("UP-015", "Formal.Properties.Universal.UP015.statement")] do
    let provider ← IO.ofExcept (← Candidates.Catalogue.loadProvider (some id))
    check s!"maintained {id} record binds to its registered version and primary"
      (provider.propertyDefinition.any fun metadata => metadata.id? == some id &&
        metadata.version? == some 1 && metadata.primary? == some primary)
  let target : TargetDescription := {
    name := "fixture.target", plutusVersion := "v3", compiledCode := "480100002221200101"
    handlers := #[], parameters := none, definitions := none, compiler := none }
  let plain ← IO.ofExcept ((Generator.generate Candidates.UP001.provider target "Metadata.Control").mapError toString)
  let described ← IO.ofExcept ((Generator.generate selected target "Metadata.Control").mapError toString)
  check "metadata does not change generated mathematical sources or observations requested"
    (plain.modules.map (·.source) == described.modules.map (·.source) &&
     plain.jobs.map (·.statement) == described.jobs.map (·.statement) &&
     plain.jobs.map (·.expected) == described.jobs.map (·.expected) &&
     described.propertyDefinition == some registered)
  IO.println "Property metadata checks passed."

end Workflow.Tests.Unit.Metadata

def main : IO Unit := Workflow.Tests.Unit.Metadata.run

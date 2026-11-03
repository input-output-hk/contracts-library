import Workflow.Preparation.Compatibility
import Workflow.Input

namespace Workflow.Tests.Unit.Compatibility

open Lean Workflow Formal.TxModels

private def parse (text : String) : Json := (Json.parse text).toOption.getD .null
private def inputs : SpendingInputs := { datum := .constr 0 [.bytes], redeemer := .constr 0 [] }
private def argument (schema : Json) : ArgumentDescription :=
  { schema, title := none, description := none }
private def target (datum : String) (redeemer : String := "{}")
    (definitions : Option Json := none) : TargetDescription := {
  name := "arbitrary.validator"
  plutusVersion := "v3"
  compiledCode := "actual-code-is-not-an-admission-allowlist"
  handlers := #[{ name := "renamed.spend", purpose := some .spend, datum := some (argument (parse datum)), redeemer := some (argument (parse redeemer)), declaredHash := none }]
  parameters := none
  definitions
  compiler := none }
private def datum : String :=
  "{\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"dataType\":\"bytes\"}]}"
private def nullary : String :=
  "{\"dataType\":\"constructor\",\"index\":0,\"fields\":[]}"

private def assertAdmission (label : String) (value : TargetDescription) (expected : Bool) : IO Unit := do
  let result := Preparation.Compatibility.check value inputs
  unless result.isOk == expected do
    throw (IO.userError s!"FAIL: {label}: {repr result}")

def run : IO Unit := do
  let original ← IO.FS.readFile "Workflow/Tests/UP001/Inputs/plutus.json"
  for selector in ["vault.vault", "vault_buggy.vault_buggy"] do
    match Workflow.Input.parse original selector with
    | .error error => throw (IO.userError s!"FAIL: original fixture: {error}")
    | .ok result => assertAdmission "original UP001 target" result.target true
  assertAdmission "typed inputs" (target datum nullary) true
  assertAdmission "untyped redeemer" (target datum) true
  assertAdmission "untyped datum" (target "{}" nullary) true
  assertAdmission "annotations have no roles"
    (target "{\"title\":\"unrelated\",\"description\":\"changed\",\"$comment\":\"any data\"}") true
  assertAdmission "singleton union"
    (target ("{\"anyOf\":[" ++ datum ++ "]}") nullary) true
  for bad in ["null", "[]", "{\"dataType\":\"bytes\"}",
      "{\"dataType\":\"constructor\",\"index\":0.5,\"fields\":[{}]}",
      "{\"dataType\":\"constructor\",\"index\":-1,\"fields\":[{}]}",
      "{\"dataType\":\"constructor\",\"index\":1,\"fields\":[{}]}",
      "{\"dataType\":\"constructor\",\"index\":0,\"fields\":[]}",
      "{\"dataType\":\"constructor\",\"index\":0,\"fields\":{}}",
      "{\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"dataType\":\"integer\"}]}",
      "{\"minLength\":0}", "{\"maxLength\":100}", "{\"enum\":[]}",
      "{\"anyOf\":[]}", "{\"anyOf\":[{},{}]}",
      "{\"$ref\":\"https://example.test/schema\"}",
      "{\"$ref\":\"#/definitions/missing\"}",
      "{\"$ref\":\"#/definitions/a~2b\"}"] do
    assertAdmission "unsupported or mismatched schema" (target bad) false
  let definitions := parse ("{\"雪/~\":" ++ datum ++ ",\"alias\":{\"$ref\":\"#/definitions/雪~1~0\"}}")
  assertAdmission "unicode escaped local pointer and alias"
    (target "{\"$ref\":\"#/definitions/alias\"}" nullary (some definitions)) true
  assertAdmission "ref with annotations"
    (target "{\"$ref\":\"#/definitions/alias\",\"title\":\"changed\"}" nullary
      (some definitions)) true
  assertAdmission "ref sibling constraint"
    (target "{\"$ref\":\"#/definitions/alias\",\"minLength\":0}" nullary
      (some definitions)) false
  assertAdmission "nested path"
    (target "{\"$ref\":\"#/definitions/outer/inner\"}" nullary
      (some (parse ("{\"outer\":{\"inner\":" ++ datum ++ "}}")))) true
  assertAdmission "cycle"
    (target "{\"$ref\":\"#/definitions/a\"}" nullary
      (some (parse "{\"a\":{\"$ref\":\"#/definitions/b\"},\"b\":{\"$ref\":\"#/definitions/a\"}}"))) false
  let percentDefinitions := parse "{\"a\":{\"dataType\":\"integer\"},\"%61\":{},\"%2F\":{},\"%25\":{}}"
  for ref in ["#/definitions/%61", "#/definitions/%2F", "#/definitions/%25"] do
    let schema := Json.mkObj [("$ref", Json.str ref)]
    let candidate := target schema.compress nullary (some percentDefinitions)
    assertAdmission "percent reference cannot select a masking literal key" candidate false
    match Preparation.Compatibility.check candidate inputs with
    | .error message =>
      unless message == "percent-encoded URI fragments are unsupported" do
        throw (IO.userError s!"FAIL: percent reference explanation: {message}")
    | .ok _ => throw (IO.userError "FAIL: percent reference was admitted")
  let mut deep := parse datum
  for _ in List.range 130 do
    deep := Json.mkObj [("anyOf", Json.arr #[deep])]
  assertAdmission "finite nesting bound" (target deep.compress nullary) false
  assertAdmission "typed bytes constraint"
    (target "{\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"dataType\":\"bytes\",\"maxLength\":32}]}" nullary) false
  assertAdmission "malformed union" (target "{\"anyOf\":{}}" nullary) false
  assertAdmission "missing nested reference path"
    (target "{\"$ref\":\"#/definitions/outer/missing\"}" nullary
      (some (parse "{\"outer\":{}}"))) false
  let base := target datum nullary
  assertAdmission "version" { base with plutusVersion := "v2" } false
  assertAdmission "empty explicit parameters" { base with parameters := some #[] } true
  assertAdmission "parameterized" { base with parameters := some #[argument (parse "{}")] } false
  assertAdmission "missing spend" { base with handlers := #[] } false
  assertAdmission "duplicate spend" { base with handlers := base.handlers ++ base.handlers } false
  assertAdmission "missing datum"
    { base with handlers := base.handlers.map fun h => { h with datum := none } } false
  assertAdmission "missing redeemer"
    { base with handlers := base.handlers.map fun h => { h with redeemer := none } } false
  assertAdmission "other purposes harmless"
    { base with handlers := base.handlers.push { name := "mint", purpose := some .mint, datum := none, redeemer := none, declaredHash := none } } true

end Workflow.Tests.Unit.Compatibility

import Workflow.Types.Target
import Formal.TxModels.Requirements

namespace Workflow.Preparation.Compatibility

open Lean Formal.TxModels

private def required (value : Option α) (message : String) : Except String α :=
  match value with
  | some value => .ok value
  | none => .error message

private def annotation (key : String) : Bool :=
  key == "title" || key == "description" || key == "$comment"

private def keys (schema : Json) : Except String (List String) := do
  return (← schema.getObj?).toList.map Prod.fst |>.filter (!annotation ·)

private def only (actual allowed : List String) : Except String Unit := do
  unless actual.all (allowed.contains ·) do
    throw "unsupported schema validation keyword"

private def decodeToken : List Char → Except String (List Char)
  | [] => .ok []
  | '~' :: '0' :: rest => ('~' :: ·) <$> decodeToken rest
  | '~' :: '1' :: rest => ('/' :: ·) <$> decodeToken rest
  | '~' :: _ => .error "invalid JSON pointer escape"
  | c :: rest => (c :: ·) <$> decodeToken rest

private def resolve (definitions : Option Json) (ref : String) : Except String Json := do
  if ref.contains '%' then
    throw "percent-encoded URI fragments are unsupported"
  let tokens := ref.splitOn "/"
  unless tokens.take 2 == ["#", "definitions"] && tokens.length > 2 do
    throw "only local definition references are supported"
  let mut current ← required definitions "missing schema definitions"
  for token in tokens.drop 2 do
    let name := ⟨← decodeToken token.toList⟩
    current ← current.getObjVal? name
  return current

/-- A finite, conservative schema subset; multi-branch unions remain unsupported. -/
private def matchShape : Nat → Option Json → List String → Json → DataShape → Except String Unit
  | 0, _, _, _, _ => .error "schema depth limit exceeded"
  | fuel + 1, definitions, seen, schema, shape => do
    let names ← keys schema
    if names.isEmpty then return ()
    if names.contains "$ref" then
      only names ["$ref"]
      let ref ← (← schema.getObjVal? "$ref").getStr?
      if seen.contains ref then throw "cyclic schema reference"
      matchShape fuel definitions (ref :: seen) (← resolve definitions ref) shape
    else if names.contains "anyOf" then
      only names ["anyOf"]
      let branches ← (← schema.getObjVal? "anyOf").getArr?
      unless branches.size == 1 do
        throw "only singleton anyOf schemas are supported; branch ambiguity is unsupported"
      matchShape fuel definitions seen branches[0]! shape
    else
      let kind ← (← schema.getObjVal? "dataType").getStr?
      match shape with
      | .bytes =>
        only names ["dataType"]
        unless kind == "bytes" do throw "model bytes do not match schema"
      | .constr index fields =>
        only names ["dataType", "index", "fields"]
        unless kind == "constructor" do throw "model constructor does not match schema"
        let declaredIndex ← (← schema.getObjVal? "index").getNat?
        unless declaredIndex == index do throw "constructor index mismatch"
        let declaredFields ← (← schema.getObjVal? "fields").getArr?
        unless declaredFields.size == fields.length do throw "constructor field count mismatch"
        for (field, expected) in declaredFields.toList.zip fields do
          matchShape fuel definitions seen field expected

/-- Admission concerns declared spending inputs, without inferring roles from names. -/
def check (target : TargetDescription) (requirements : SpendingInputs) : Except String Unit := do
  unless target.plutusVersion == "v3" do throw "model requires Plutus V3"
  unless (target.parameters.getD #[]).isEmpty do throw "parameterized targets are unsupported"
  let spending := target.handlers.filter (·.purpose == some .spend)
  unless spending.size == 1 do throw "model requires exactly one declared spending handler"
  let handler ← required spending[0]? "spending handler is missing"
  let datum ← required handler.datum "spending datum schema is missing"
  let redeemer ← required handler.redeemer "spending redeemer schema is missing"
  matchShape 128 target.definitions [] datum.schema requirements.datum
  matchShape 128 target.definitions [] redeemer.schema requirements.redeemer

end Workflow.Preparation.Compatibility

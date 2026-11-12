import Workflow.Types.Target
import PlutusCore.UPLC.ScriptEncoding.Basic

namespace Workflow.Input

open Lean

inductive ErrorKind where
  | malformedJson | missingField | malformedField | unsupported
  | selection | inconsistent | decoding | io
  deriving BEq, Repr

structure Error where
  kind : ErrorKind
  path : String
  message : String
  deriving Repr

instance : ToString Error where
  toString error := s!"{error.path}: {error.message}"

private def fail (kind : ErrorKind) (path message : String) : Except Error α :=
  .error ⟨kind, path, message⟩

private def object (value : Json) (path : String) : Except Error Unit :=
  match value with
  | .obj _ => .ok ()
  | _ => fail .malformedField path "expected an object"

private def field (value : Json) (key : String) : Option Json :=
  (value.getObjVal? key).toOption

private def required (value : Json) (key path : String) : Except Error Json :=
  match field value key with
  | some result => .ok result
  | none => fail .missingField path s!"missing required field '{key}'"

private def string (value : Json) (path : String) : Except Error String := do
  let result ← value.getStr?.mapError fun _ => ⟨.malformedField, path, "expected a string"⟩
  if result.trim.isEmpty then fail .malformedField path "expected a nonempty string"
  else return result

private def requiredString (value : Json) (key path : String) : Except Error String := do
  string (← required value key path) path

private def optionalString (value : Json) (key path : String) : Except Error (Option String) := do
  match field value key with
  | none => return none
  | some item =>
    return some (← item.getStr?.mapError fun _ =>
      ⟨.malformedField, path, "expected a string when present"⟩)

private def optionalObject (value : Json) (key path : String) : Except Error (Option Json) := do
  match field value key with
  | none => return none
  | some item => object item path; return some item

private def argument (value : Json) (path : String) : Except Error ArgumentDescription := do
  object value path
  let schema ← required value "schema" s!"{path}.schema"
  object schema s!"{path}.schema"
  return { schema
           title := ← optionalString value "title" s!"{path}.title"
           description := ← optionalString value "description" s!"{path}.description" }

private def optionalArgument (value : Json) (key path : String) :
    Except Error (Option ArgumentDescription) := do
  match field value key with
  | none => return none
  | some item => return some (← argument item path)

private def parameters (value : Json) (path : String) :
    Except Error (Option (Array ArgumentDescription)) := do
  match field value "parameters" with
  | none => return none
  | some item =>
    let items ← item.getArr?.mapError fun _ =>
      ⟨.malformedField, path, "expected an array when present"⟩
    let mut result := #[]
    for i in [:items.size] do
      result := result.push (← argument items[i]! s!"{path}[{i}]")
    return some result

private def purpose (name path : String) : Except Error (Option Purpose) :=
  match name with
  | "spend" => .ok (some .spend)
  | "mint" => .ok (some .mint)
  | "withdraw" => .ok (some .withdraw)
  | "publish" => .ok (some .publish)
  | "vote" => .ok (some .vote)
  | "propose" => .ok (some .propose)
  | "else" => .ok none
  | _ => fail .unsupported path s!"unsupported handler purpose '{name}'"

private structure Entry where
  name : String
  target : String
  shortName : String
  handler : String
  value : Json
  path : String

private def entry (value : Json) (index : Nat) : Except Error Entry := do
  let path := s!"validators[{index}]"
  object value path
  let name ← requiredString value "title" s!"{path}.title"
  match name.splitOn "." with
  | [moduleName, validator, handler] =>
    if moduleName.isEmpty || validator.isEmpty || handler.isEmpty then
      fail .malformedField s!"{path}.title" "empty validator-name component"
    else return { name, target := s!"{moduleName}.{validator}", shortName := validator,
                  handler, value, path }
  | _ =>
    fail .unsupported s!"{path}.title" "expected the supported module.validator.handler title profile"

private def validateCode (code path : String) : Except Error Unit := do
  let _ ← PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex? code
    |>.mapError fun message => ⟨.decoding, path, message⟩
  -- The library helper decodes a CBOR prefix; require the supplied artifact to end there.
  let some bytes := PlutusCore.UPLC.ScriptEncoding.Internal.hexStringToString code.data []
    | fail .decoding path "could not decode hexadecimal input"
  let some (remaining, _) := PlutusCore.Cbor.decodeLargeBytestring ⟨bytes⟩
    | fail .decoding path "could not decode CBOR input"
  unless remaining.isEmpty do
    fail .decoding path "unexpected bytes after the compiled script"

private structure Document where
  blueprint : Json
  preamble : Json
  version : String
  entries : Array Entry

private def document (source : String) : Except Error Document := do
  let blueprint ← Json.parse source |>.mapError fun message =>
    ⟨.malformedJson, "$", message⟩
  object blueprint "$"
  let preamble ← required blueprint "preamble" "preamble"
  object preamble "preamble"
  let version ← requiredString preamble "plutusVersion" "preamble.plutusVersion"
  unless version == "v3" do
    fail .unsupported "preamble.plutusVersion" s!"unsupported Plutus version '{version}'"
  let validators ← required blueprint "validators" "validators"
  let values ← validators.getArr?.mapError fun _ =>
    ⟨.malformedField, "validators", "expected an array"⟩
  let mut entries := #[]
  for i in [:values.size] do
    entries := entries.push (← entry values[i]! i)
  return { blueprint, preamble, version, entries }

/-- Discover logical validators without interpreting their compiled code. -/
def discover (source : String) : Except Error (Array String) := do
  let parsed ← document source
  let mut names := #[]
  for item in parsed.entries do
    unless names.contains item.target do names := names.push item.target
  return names

/-- Read one validator using the current Aiken-style blueprint title profile.
    Schema content is preserved, not translated or checked for proof applicability. -/
def parse (source selector : String) : Except Error InputResult := do
  let parsed ← document source
  let mut candidateNames : Array String := #[]
  for item in parsed.entries do
    if (item.target == selector || item.shortName == selector) && !candidateNames.contains item.target then
      candidateNames := candidateNames.push item.target
  if candidateNames.isEmpty then
    fail .selection "validator" s!"no validator matches '{selector}'"
  if candidateNames.size != 1 then
    fail .selection "validator" s!"ambiguous validator '{selector}': {String.intercalate ", " candidateNames.toList}"
  let name := candidateNames[0]!
  let selected := parsed.entries.filter (·.target == name)
  let some first := selected[0]?
    | fail .selection "validator" "the selected validator has no entries"
  let code ← requiredString first.value "compiledCode" s!"{first.path}.compiledCode"
  validateCode code s!"{first.path}.compiledCode"
  let params ← parameters first.value s!"{first.path}.parameters"
  let mut handlers := #[]
  let mut seen : Array String := #[]
  for item in selected do
    if seen.contains item.handler then
      fail .inconsistent s!"{item.path}.title" s!"duplicate handler '{item.handler}'"
    seen := seen.push item.handler
    let otherCode ← requiredString item.value "compiledCode" s!"{item.path}.compiledCode"
    unless otherCode == code do
      fail .inconsistent s!"{item.path}.compiledCode" "handlers have different compiled code"
    let otherParams ← parameters item.value s!"{item.path}.parameters"
    unless otherParams == params do
      fail .inconsistent s!"{item.path}.parameters" "handlers have different parameter descriptions"
    let handlerPurpose ← purpose item.handler s!"{item.path}.title"
    let redeemer ← optionalArgument item.value "redeemer" s!"{item.path}.redeemer"
    if handlerPurpose.isSome && redeemer.isNone then
      fail .missingField s!"{item.path}.redeemer" "a declared handler requires a redeemer description"
    handlers := handlers.push {
      name := item.name, purpose := handlerPurpose, redeemer
      datum := ← optionalArgument item.value "datum" s!"{item.path}.datum"
      declaredHash := ← optionalString item.value "hash" s!"{item.path}.hash" }
  return {
    target := { name, plutusVersion := parsed.version, compiledCode := code, handlers,
                parameters := params
                definitions := ← optionalObject parsed.blueprint "definitions" "definitions"
                compiler := ← optionalObject parsed.preamble "compiler" "preamble.compiler" }
    sourceText := source
    sourcePath := none }

/-- Read once and retain readable source text even when validation fails. -/
def readWithSource (path : System.FilePath) (selector : String) :
    IO (Option String × Except Error InputResult) := do
  try
    let source ← IO.FS.readFile path
    return (some source, (parse source selector).map fun result => { result with sourcePath := some path })
  catch error =>
    return (none, .error ⟨.io, path.toString, error.toString⟩)

/-- Read without modifying the input; retain the exact text separately from target metadata. -/
def read (path : System.FilePath) (selector : String) : IO (Except Error InputResult) := do
  return (← readWithSource path selector).2

end Workflow.Input

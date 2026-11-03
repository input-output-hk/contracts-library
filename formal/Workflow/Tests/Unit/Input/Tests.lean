import Workflow.Input

open Lean Workflow
open Workflow.Input

namespace Workflow.Tests.Unit.Input

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def accepted (source selector : String) : IO InputResult := do
  match Workflow.Input.parse source selector with
  | .ok result => return result
  | .error error => throw (IO.userError s!"unexpected input error: {error}")

private def rejected (label source selector : String) (kind : ErrorKind)
    (path : String) : IO Unit := do
  match Workflow.Input.parse source selector with
  | .ok _ => throw (IO.userError s!"FAIL: {label}: malformed input was accepted")
  | .error error =>
    check s!"{label}: error category" (error.kind == kind)
    check s!"{label}: error location" (error.path == path)
    check s!"{label}: error explanation" (!error.message.isEmpty)

private def discovered (source : String) : IO (Array String) := do
  match Workflow.Input.discover source with
  | .ok names => return names
  | .error error => throw (IO.userError s!"unexpected discovery error: {error}")

private def discoveryRejected (label source : String) (kind : ErrorKind)
    (path : String) : IO Unit := do
  match Workflow.Input.discover source with
  | .ok _ => throw (IO.userError s!"FAIL: {label}: malformed document was discovered")
  | .error error =>
    check s!"{label}: discovery error category" (error.kind == kind)
    check s!"{label}: discovery error location" (error.path == path)

private def dropField (value : Json) (key : String) : Json :=
  match value with
  | .obj fields => .obj (fields.erase key)
  | _ => value

private def validators (value : Json) : Array Json :=
  ((value.getObjVal? "validators").toOption.bind (·.getArr?.toOption)).getD #[]

private def updateEntry (value : Json) (index : Nat) (f : Json → Json) : Json :=
  let items := validators value
  value.setObjVal! "validators" (.arr (items.set! index (f items[index]!)))

private def updateAlpha (value : Json) (f : Json → Json) : Json :=
  updateEntry (updateEntry value 0 f) 1 f

private def updateVersion (value : Json) (f : Json → Json) : Json :=
  value.setObjVal! "preamble" (f ((value.getObjVal? "preamble").toOption.getD .null))

def run : IO Unit := do
  let path : System.FilePath := "Workflow/Tests/Unit/Input/Fixtures/blueprint.json"
  let original ← IO.FS.readFile path
  let blueprint ← match Json.parse original with
    | .ok result => pure result
    | .error message => throw (IO.userError message)
  check "discovery groups handlers and preserves validator order"
    ((← discovered original) == #["samples.alpha", "other.beta"])
  check "empty blueprint has no discovered validators"
    ((← discovered (blueprint.setObjVal! "validators" (.arr #[])).compress) == #[])
  let result ← accepted original "samples.alpha"
  check "canonical selection" (result.target.name == "samples.alpha")
  check "original encoded code" (result.target.compiledCode == "480100002221200101")
  check "source snapshot" (result.sourceText == original && result.sourcePath.isNone)
  check "handler grouping" (result.target.handlers.size == 2)
  check "fallback is not a declared purpose" (result.target.declaredPurposes == #[.spend])
  let some primary := result.target.handlers[0]?
    | throw (IO.userError "missing primary handler")
  check "optional metadata is absent" primary.declaredHash.isNone
  check "schema definitions preserved" (result.target.definitions ==
    (blueprint.getObjVal? "definitions").toOption)
  let alphaParams := result.target.parameters.getD #[]
  check "parameter count" (alphaParams.size == 2)
  let some owner := alphaParams[0]? | throw (IO.userError "missing owner parameter")
  let some threshold := alphaParams[1]? | throw (IO.userError "missing threshold parameter")
  check "parameter order" (owner.title == some "owner" && threshold.title == some "threshold")
  check "parameter schema preserved" (owner.schema ==
    Json.mkObj [("dataType", .str "bytes")])
  let short ← accepted original "alpha"
  check "unique short selector" (short.target == result.target)
  let beta ← accepted original "other.beta"
  check "second validator selected independently" (beta.target.name == "other.beta" &&
    beta.target.handlers.size == 1 && beta.target.declaredPurposes == #[.mint])
  check "absent parameters stay absent" beta.target.parameters.isNone

  let onlyAlpha := blueprint.setObjVal! "validators" (.arr (validators blueprint |>.extract 0 2))
  let withoutOther ← accepted onlyAlpha.compress "samples.alpha"
  check "unrelated validator does not change target" (withoutOther.target == result.target)
  let brokenOther := updateEntry blueprint 2 (·.setObjVal! "compiledCode" (.str "zz"))
  check "invalid validator code does not block discovery"
    ((← discovered brokenOther.compress) == #["samples.alpha", "other.beta"])
  let independent ← accepted brokenOther.compress "alpha"
  check "unselected code is not interpreted" (independent.target == result.target)
  rejected "discovered invalid validator fails its own preparation"
    brokenOther.compress "other.beta" .decoding "validators[2].compiledCode"
  let mint := ((validators blueprint)[2]!.setObjVal! "title" (.str "samples.alpha.mint"))
    |>.setObjVal! "parameters" (((validators blueprint)[0]!.getObjVal? "parameters").toOption.getD .null)
  let multiple := blueprint.setObjVal! "validators" (.arr ((validators blueprint).push mint))
  let multi ← accepted multiple.compress "alpha"
  check "one validator can declare multiple purposes" (multi.target.handlers.size == 3 &&
    multi.target.declaredPurposes == #[.spend, .mint])
  let modulePath := updateAlpha blueprint fun item =>
    let suffix := ((item.getObjVal? "title").toOption.bind (·.getStr?.toOption)).getD ""
      |>.splitOn "." |>.getLast!
    item.setObjVal! "title" (.str s!"folder/module.alpha.{suffix}")
  let nested ← accepted modulePath.compress "folder/module.alpha"
  check "module paths preserve canonical identity" (nested.target.name == "folder/module.alpha")
  check "discovery retains canonical module paths"
    ((← discovered modulePath.compress) == #["folder/module.alpha", "other.beta"])
  let emptyParams := updateAlpha blueprint (·.setObjVal! "parameters" (.arr #[]))
  let empty ← accepted emptyParams.compress "alpha"
  check "empty parameters remain distinct from absence" (empty.target.parameters == some #[])
  let noParams := updateAlpha blueprint (fun item => dropField item "parameters")
  let noParameters ← accepted noParams.compress "alpha"
  check "no parameter application" (noParameters.target.compiledCode == result.target.compiledCode)
  let withoutOptional := dropField
    (updateVersion blueprint (fun preamble => dropField preamble "compiler")) "definitions"
  let optional ← accepted withoutOptional.compress "beta"
  check "optional compiler and definitions stay absent"
    (optional.target.compiler.isNone && optional.target.definitions.isNone)

  rejected "malformed JSON" "{" "alpha" .malformedJson "$"
  discoveryRejected "malformed JSON" "{" .malformedJson "$"
  discoveryRejected "non-array validators" (blueprint.setObjVal! "validators" .null).compress
    .malformedField "validators"
  rejected "non-object root" "[]" "alpha" .malformedField "$"
  rejected "missing preamble" (dropField blueprint "preamble").compress "alpha"
    .missingField "preamble"
  rejected "non-object preamble" (blueprint.setObjVal! "preamble" .null).compress "alpha"
    .malformedField "preamble"
  rejected "missing version" (updateVersion blueprint (fun p => dropField p "plutusVersion")).compress
    "alpha" .missingField "preamble.plutusVersion"
  for version in ["v1", "v2", "v4"] do
    rejected s!"unsupported version {version}"
      (updateVersion blueprint (·.setObjVal! "plutusVersion" (.str version))).compress
      "alpha" .unsupported "preamble.plutusVersion"
    discoveryRejected s!"unsupported discovery version {version}"
      (updateVersion blueprint (·.setObjVal! "plutusVersion" (.str version))).compress
      .unsupported "preamble.plutusVersion"
  rejected "non-string version"
    (updateVersion blueprint (·.setObjVal! "plutusVersion" (.num 3))).compress
    "alpha" .malformedField "preamble.plutusVersion"
  rejected "missing validators" (dropField blueprint "validators").compress "alpha"
    .missingField "validators"
  rejected "non-array validators" (blueprint.setObjVal! "validators" .null).compress "alpha"
    .malformedField "validators"
  rejected "missing selection" original "absent" .selection "validator"
  rejected "empty selector" original "" .selection "validator"
  let ambiguous := blueprint.setObjVal! "validators" (.arr
    ((validators blueprint).push ((validators blueprint)[2]!.setObjVal! "title" (.str "other.alpha.mint"))))
  rejected "ambiguous short selection" ambiguous.compress "alpha" .selection "validator"
  let explicit ← accepted ambiguous.compress "samples.alpha"
  check "canonical selection survives short-name collision" (explicit.target == result.target)
  rejected "missing title" (updateEntry blueprint 0 (fun item => dropField item "title")).compress
    "alpha" .missingField "validators[0].title"
  rejected "unsupported title profile"
    (updateEntry blueprint 0 (·.setObjVal! "title" (.str "alpha"))).compress
    "alpha" .unsupported "validators[0].title"
  discoveryRejected "unsupported title profile"
    (updateEntry blueprint 0 (·.setObjVal! "title" (.str "alpha"))).compress
    .unsupported "validators[0].title"
  rejected "missing code" (updateEntry blueprint 0 (fun item => dropField item "compiledCode")).compress
    "alpha" .missingField "validators[0].compiledCode"
  rejected "empty code" (updateEntry blueprint 0 (·.setObjVal! "compiledCode" (.str ""))).compress
    "alpha" .malformedField "validators[0].compiledCode"
  for (label, code) in [("odd hex", "0"), ("invalid hex", "zz"), ("truncated CBOR", "48"),
      ("invalid program", "4100"), ("trailing bytes", "48010000222120010100")] do
    rejected label (updateAlpha blueprint (·.setObjVal! "compiledCode" (.str code))).compress
      "alpha" .decoding "validators[0].compiledCode"
  rejected "different handler code"
    (updateEntry blueprint 1 (·.setObjVal! "compiledCode" (.str "4100"))).compress
    "alpha" .inconsistent "validators[1].compiledCode"
  rejected "inconsistent parameters"
    (updateEntry blueprint 1 (fun item => dropField item "parameters")).compress
    "alpha" .inconsistent "validators[1].parameters"
  rejected "non-array parameters"
    (updateAlpha blueprint (·.setObjVal! "parameters" .null)).compress
    "alpha" .malformedField "validators[0].parameters"
  rejected "missing parameter schema"
    (updateAlpha blueprint (·.setObjVal! "parameters" (.arr #[Json.mkObj []]))).compress
    "alpha" .missingField "validators[0].parameters[0].schema"
  rejected "non-object schema"
    (updateAlpha blueprint (·.setObjVal! "parameters"
      (.arr #[Json.mkObj [("schema", .null)]]))).compress
    "alpha" .malformedField "validators[0].parameters[0].schema"
  rejected "missing redeemer"
    (updateEntry blueprint 0 (fun item => dropField item "redeemer")).compress
    "alpha" .missingField "validators[0].redeemer"
  rejected "invalid optional hash"
    (updateEntry blueprint 0 (·.setObjVal! "hash" .null)).compress
    "alpha" .malformedField "validators[0].hash"
  rejected "invalid definitions"
    (blueprint.setObjVal! "definitions" (.arr #[])).compress
    "alpha" .malformedField "definitions"
  let duplicate := blueprint.setObjVal! "validators" (.arr
    ((validators blueprint).push (validators blueprint)[0]!))
  rejected "duplicate handler" duplicate.compress "alpha" .inconsistent "validators[3].title"
  let unsupported := updateEntry blueprint 2 (·.setObjVal! "title" (.str "other.beta.unknown"))
  check "unsupported handler purpose is deferred to selected preparation"
    ((← discovered unsupported.compress) == #["samples.alpha", "other.beta"])
  rejected "unsupported selected purpose" unsupported.compress "beta"
    .unsupported "validators[2].title"
  let selected ← accepted unsupported.compress "alpha"
  check "unrelated unsupported handler is not selected" (selected.target == result.target)

  match ← Workflow.Input.read path "alpha" with
  | .ok readResult =>
    check "file and text readers agree" (readResult.target == result.target)
    check "source path retained" (readResult.sourcePath == some path)
    check "original text retained" (readResult.sourceText == original)
  | .error error => throw (IO.userError s!"file read failed: {error}")
  check "source file unchanged" ((← IO.FS.readFile path) == original)
  match ← Workflow.Input.read "Workflow/Tests/Unit/Input/Fixtures/missing.json" "alpha" with
  | .error error => check "file errors are explicit" (error.kind == .io)
  | .ok _ => throw (IO.userError "FAIL: missing file was accepted")
  IO.println "Input fixture checks passed."

end Workflow.Tests.Unit.Input

def main : IO Unit := Workflow.Tests.Unit.Input.run

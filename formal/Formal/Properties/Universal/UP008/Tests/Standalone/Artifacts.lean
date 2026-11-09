import Lean.Data.Json
import Formal.Properties.Universal.UP008.Tests.Standalone.EnforcingControl

namespace Tests.UP008

private def checkSourceHash (path expected : String) : IO Unit := do
  let result ← IO.Process.output { cmd := "sha256sum", args := #["--", path] }
  unless result.exitCode == 0 && result.stdout.startsWith (expected ++ " ") do
    throw (IO.userError s!"UP008 source hash mismatch: {path}")

private def checkProgram (path title hash compiler : String)
    (expected : PlutusCore.UPLC.Term.Program) (code : Option String := none) : IO Unit := do
  let blueprint ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  let version ← IO.ofExcept (preamble.getObjValAs? String "plutusVersion")
  let compilerInfo ← IO.ofExcept (preamble.getObjVal? "compiler")
  let compilerVersion ← IO.ofExcept (compilerInfo.getObjValAs? String "version")
  unless version == "v3" && compilerVersion == compiler do
    throw (IO.userError s!"UP008 blueprint version mismatch: {path}")
  let validators ← IO.ofExcept do (← blueprint.getObjVal? "validators").getArr?
  let entries := validators.filter fun entry =>
    (entry.getObjValAs? String "title").toOption == some title
  unless entries.size == 1 do
    throw (IO.userError s!"UP008 requires one blueprint entry: {title}")
  for entry in entries do
    let actualCode ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
    let actualHash ← IO.ofExcept (entry.getObjValAs? String "hash")
    unless actualHash == hash && code.all (· == actualCode) do
      throw (IO.userError s!"UP008 compiled code or hash mismatch: {title}")
    let decoded ← IO.ofExcept
      (PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex? actualCode)
    unless reprStr decoded == reprStr expected do
      throw (IO.userError s!"UP008 embedded proof program differs from blueprint: {title}")
    if let .ok parameters := entry.getObjVal? "parameters" then
      let parameters ← IO.ofExcept parameters.getArr?
      unless parameters.isEmpty do
        throw (IO.userError s!"UP008 does not accept unapplied parameters: {title}")

/-- Bind both embedded proof programs to tracked blueprints and enforcing source files.
    The standalone checks do not require generated Aiken build output. -/
def checkArtifacts : IO Unit := do
  checkSourceHash "Formal/Properties/Universal/UP008/Tests/Standalone/Project/validators/enforcing.ak"
    "09675058708cb376b8560dcb33b49c3612837a4c3641724dd323a07297c2d56e"
  checkSourceHash "Formal/Properties/Universal/UP008/Tests/Standalone/Project/aiken.toml"
    "6ce05f697ac862022b9f9001ba4acb35081c04c39743ada51877fcd704cd1d5d"
  checkSourceHash "Formal/Properties/Universal/UP008/Tests/Standalone/Project/aiken.lock"
    "1c39ab261e3a6811d31868ba430d81a6a6012347ad5904262f04b7c441824091"
  checkSourceHash "Formal/Properties/Universal/UP008/Tests/Standalone/Inputs/control.json"
    "2c2a087023f824ebc5911e2dd7fc046dff1a3cb8b9cd8f00ab3376e3003972f1"
  checkProgram "../onchain/plutus.json" "linear_vesting.linear_vesting.spend"
    Formal.Vesting.Linear.Blueprint.scriptHashHex "v1.1.22+39d6b04"
    Formal.Vesting.Linear.Blueprint.program
  checkProgram "Formal/Properties/Universal/UP008/Tests/Standalone/Inputs/control.json" "enforcing.enforcing.spend"
    Enforcing.declaredScriptHash "v1.1.21+42babe5" Enforcing.program
    (some Enforcing.compiledCode)
  IO.println "UP008: source hashes and both embedded programs match their recorded artifacts."

/-- Optional source rebuild check. Run `aiken build` in Project before this entrypoint. -/
def checkRebuiltControl : IO Unit := do
  checkArtifacts
  checkProgram "Formal/Properties/Universal/UP008/Tests/Standalone/Project/plutus.json" "enforcing.enforcing.spend"
    Enforcing.declaredScriptHash "v1.1.21+42babe5" Enforcing.program
    (some Enforcing.compiledCode)
  IO.println "UP008: rebuilt control matches the frozen proof program."

end Tests.UP008

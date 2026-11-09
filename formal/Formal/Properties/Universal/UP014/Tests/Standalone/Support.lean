import Lean
import Formal.Vesting.Linear.Blueprint.ContinuationOtherDatum

namespace Tests.UP014.Control

open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3 (Credential ScriptContext validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint (args claim)

/-- Compiled from Project/validators/continuation_gate.ak with Aiken v1.1.21+42babe5,
    Plutus V3, and aiken-lang/stdlib v3.0.0. This fixture deliberately ignores datums. -/
def compiledCode : String := "59011801010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cc0200092225980099b8748008c01cdd500144c8c8cc896600266e1d2000300b3754005133225980099b8748008c034dd5180898071baa3011300e37546002601c6ea800a266ebcc044c038dd5180898071baa30113758602260246024601c6ea801cc044c038dd5180898071baa3001300e3754005164030601e60186ea80088c040c0440062c8050c8cc004004dd6180718059baa0042259800800c530103d87a80008992cc004cdd7980818069baa001004899ba548000cc03c0052f5c11330030033011002402c601e0028068c034c038008c030004c020dd50014590060c020004c00cdd5004452689b2b20021"

def scriptHashHex : String := "4acb3c5a1cc296397cc47d74bd21269e2fa7c64264851de8bc89306b"

/-- SHA-256 of the single-CBOR compiled bytes, not their hexadecimal text. -/
def compiledSha256 : String := "1f1c9e2c4cf6cbd773ff7dd5d29f1f83147a84e4d6e42c75306440d23314a3f9"

def program : Program := singleCborEncodedScriptFromHexM "59011801010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cc0200092225980099b8748008c01cdd500144c8c8cc896600266e1d2000300b3754005133225980099b8748008c034dd5180898071baa3011300e37546002601c6ea800a266ebcc044c038dd5180898071baa30113758602260246024601c6ea801cc044c038dd5180898071baa3001300e3754005164030601e60186ea80088c040c0440062c8050c8cc004004dd6180718059baa0042259800800c530103d87a80008992cc004cdd7980818069baa001004899ba548000cc03c0052f5c11330030033011002402c601e0028068c034c038008c030004c020dd50014590060c020004c00cdd5004452689b2b20021"

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin program (args ctx) fuel

/-- Bind the original positive check to its tracked blueprint, without rebuilding it. -/
def checkVestingArtifact : IO Unit := do
  let blueprint ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile "../onchain/plutus.json"))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  let version ← IO.ofExcept (preamble.getObjValAs? String "plutusVersion")
  unless version == "v3" do
    throw (IO.userError "UP014 vesting fixture requires Plutus V3")
  let validators ← IO.ofExcept do (← blueprint.getObjVal? "validators").getArr?
  let entries := validators.filter fun entry =>
    (entry.getObjValAs? String "title").toOption == some "linear_vesting.linear_vesting.spend"
  unless entries.size == 1 do
    throw (IO.userError "UP014 vesting fixture requires its unique spend entry")
  for entry in entries do
    let code ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
    let hash ← IO.ofExcept (entry.getObjValAs? String "hash")
    unless hash == Formal.Vesting.Linear.Blueprint.scriptHashHex do
      throw (IO.userError "UP014 vesting fixture hash metadata changed")
    if let .ok parameters := entry.getObjVal? "parameters" then
      let parameters ← IO.ofExcept parameters.getArr?
      unless parameters.isEmpty do
        throw (IO.userError "UP014 vesting fixture unexpectedly has unapplied parameters")
    let decoded ← IO.ofExcept
      (PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex? code)
    unless reprStr decoded == reprStr Formal.Vesting.Linear.Blueprint.program do
      throw (IO.userError "UP014 vesting proof program differs from the tracked blueprint")
  IO.println "UP014 vesting program matches the tracked unparameterized V3 artifact."

/-- Compare a V3 blueprint and decoded program with the embedded fixture.
    The blueprint hash is checked as recorded metadata, not independently recomputed. -/
def checkControlBlueprint (path : System.FilePath) : IO Unit := do
  let blueprint ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  let version ← IO.ofExcept (preamble.getObjValAs? String "plutusVersion")
  let compiler ← IO.ofExcept (preamble.getObjVal? "compiler")
  let compilerVersion ← IO.ofExcept (compiler.getObjValAs? String "version")
  unless version == "v3" && compilerVersion == "v1.1.21+42babe5" do
    throw (IO.userError "UP014 control compiler or Plutus version changed")
  let validators ← IO.ofExcept do (← blueprint.getObjVal? "validators").getArr?
  let expectedTitles := #["continuation_gate.continuation_gate.spend",
    "continuation_gate.continuation_gate.else"]
  unless validators.size == expectedTitles.size do
    throw (IO.userError "UP014 control handler count changed")
  for entry in validators do
    let title ← IO.ofExcept (entry.getObjValAs? String "title")
    let code ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
    let hash ← IO.ofExcept (entry.getObjValAs? String "hash")
    unless expectedTitles.contains title && code == compiledCode && hash == scriptHashHex do
      throw (IO.userError "UP014 control differs from the compiled source")
    if let .ok parameters := entry.getObjVal? "parameters" then
      let parameters ← IO.ofExcept parameters.getArr?
      unless parameters.isEmpty do
        throw (IO.userError "UP014 control unexpectedly has unapplied parameters")
    let decoded ← IO.ofExcept
      (PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex? code)
    unless reprStr decoded == reprStr program do
      throw (IO.userError "UP014 embedded proof program differs from the compiled bytes")
  IO.println s!"UP014 control matches the unparameterized V3 artifact at {path}."

/-- Normal standalone identity check uses the frozen, tracked blueprint. -/
def checkArtifact : IO Unit :=
  checkControlBlueprint "Formal/Properties/Universal/UP014/Tests/Standalone/Inputs/control.json"

/-- Optional source-rebuild check requires running Aiken in Project first. -/
def checkRebuiltArtifact : IO Unit :=
  checkControlBlueprint "Formal/Properties/Universal/UP014/Tests/Standalone/Project/plutus.json"

-- Exact Claim propositions with only the evaluated program replaced.
def continuationOtherDatum_claim : Prop :=
    ∀ p (x201 : Credential) (x202 : Credential) (x203 : Int) (x204 : Int) (x205 : Int),
      validScriptContext (claim p) = true →
      accepts ledgerFuel (claim p) →
      rejects ledgerFuel (redirectContinuations (claim p)) →
      (firstContinuation? (claim p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false →
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true →
      rejects ledgerFuel (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))


/-- `continuationOtherDatum_claim` applies: some valid accepted `claim` transaction gives a valid
    changed transaction, providing a witness for the guards above. -/
def continuationOtherDatum_claim_applies : Prop :=
    ∃ p, ∃ (x201 : Credential), ∃ (x202 : Credential), ∃ (x203 : Int), ∃ (x204 : Int), ∃
      (x205 : Int),
      validScriptContext (claim p) = true ∧
      accepts ledgerFuel (claim p) ∧
      rejects ledgerFuel (redirectContinuations (claim p)) ∧
      (firstContinuation? (claim p)).any (fun o => o.txOutDatum == .OutputDatum (Data.Constr 0
        [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204),
        (Data.I x205)])) = false ∧
      validScriptContext (changeContinuation (claim p) (fun o =>
        { o with txOutDatum := .OutputDatum (Data.Constr 0 [(IsData.toData x201), (IsData.toData x202), (Data.List []), (Data.I x203), (Data.I x204), (Data.I x205)]) }))
        = true

end Tests.UP014.Control

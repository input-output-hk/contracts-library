import Lean.Data.Json
import Formal.Settings.Blueprint.Tx

namespace Tests.UP016.VerifyArtifact

open Lean (Json)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Program Term)
open PlutusCore.Crypto.Hash (sha2_256 blake2b_224)
open Formal.Settings.Blueprint

def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def fromHex (hex : String) : IO ByteString := do
  let some bytes := PlutusCore.UPLC.ScriptEncoding.Internal.hexStringToString hex.toList []
    | throw (IO.userError "Invalid hexadecimal artifact or parameter")
  pure ⟨String.mk bytes⟩

def toHex (bytes : ByteString) : String :=
  String.join (bytes.data.toList.map fun c => BitVec.toHex c.toUInt8.toBitVec)

def decodeProgram (hex : String) : IO Program := do
  let bytes ← fromHex hex
  let some (rest, flat) := PlutusCore.Cbor.decodeLargeBytestring bytes.data
    | throw (IO.userError "Invalid single-CBOR program")
  require rest.isEmpty "Trailing bytes after the program CBOR"
  let some decoded := PlutusCore.UPLC.FlatEncoding.decodeProgramFromByteString flat
    | throw (IO.userError "Invalid Flat program")
  pure decoded

def decodeParameter (hex : String) : IO Data := do
  let bytes ← fromHex hex
  let some (rest, datum) := PlutusCore.Cbor.decodeData bytes.data
    | throw (IO.userError "Invalid parameter CBOR")
  require rest.isEmpty "Trailing bytes after a parameter"
  pure datum

def fieldEquals (json : Json) (key expected : String) : IO Unit := do
  let actual ← IO.ofExcept (json.getObjValAs? String key)
  require (actual == expected) s!"Unexpected {key}: {actual}"

def check : IO Unit := do
  let metadata ← IO.ofExcept (Json.parse
    (← IO.FS.readFile "Formal/Settings/Blueprint/validator-metadata.json"))
  for (key, expected) in [
      ("validator_name", "settings.settings.mint"),
      ("source_repository", "https://github.com/input-output-hk/contracts-library"),
      ("source_commit", "96c9f328060b1664402134d71fdf0bc4a838fba7"),
      ("file_name", "onchain/validators/settings.ak"),
      ("sha256", "aa99e9118721bdfe26fd6abe059cfd1a1f8b32d2b5a3634168aeb86ed246cc75"),
      ("cbor_format", "single_cbor_hex"), ("plutus_version", "v3"),
      ("parameterization_state", "fully_applied"),
      ("compiler_name", "Aiken"), ("compiler_version", "v1.1.22+39d6b04")] do
    fieldEquals metadata key expected
  let source ← IO.FS.readBinFile "../onchain/validators/settings.ak"
  let sourceBytes : ByteString := ⟨String.mk (source.toList.map Char.ofUInt8)⟩
  require (toHex (sha2_256 sourceBytes) ==
    "aa99e9118721bdfe26fd6abe059cfd1a1f8b32d2b5a3634168aeb86ed246cc75")
    "Recorded validator source digest changed"
  let hex ← IO.ofExcept (metadata.getObjValAs? String "cbor_hex")
  let bytes ← fromHex hex
  require (bytes.data.length == 2679) "Applied artifact size changed"
  require (toHex (sha2_256 bytes) ==
    "527f551e2b615d50ce44679e9bc585552cac8c549a0637864eb93e4c34f2ec50")
    "Applied artifact byte digest changed"
  let policy := blake2b_224 (ByteString.cons 3 bytes)
  require (toHex policy == scriptHashHex && policy == ownPolicy &&
    scriptHashHex == "50dc52e6bf8db417d8e5b70bbd2c1caa6a45a5ca7854a51d99b63e60")
    "Applied Plutus V3 policy identity changed"
  let applied ← decodeProgram hex
  require (reprStr applied == reprStr program) "Embedded proof program differs from metadata"
  let parameters ← IO.ofExcept (metadata.getObjValAs? (Array String) "applied_parameters")
  let expectedParameters := #[
    "d879825820111111111111111111111111111111111111111111111111111111111111111100",
    "d87981581c22222222222222222222222222222222222222222222222222222222",
    "d87981581c33333333333333333333333333333333333333333333333333333333",
    "19ea60", "455550303136"]
  require (parameters == expectedParameters) "Applied parameter values or order changed"
  let dataParameters ← parameters.toList.mapM decodeParameter
  let proposer : ByteString := ⟨String.mk (List.replicate 28 (Char.ofNat 0x22))⟩
  require (dataParameters == [
    .Constr 0 [.B seedTxId, .I 0], .Constr 0 [.B proposer],
    .Constr 0 [.B applyKey], .I 60000, .B tokenName])
    "Applied parameter values differ from the fixed model"
  let blueprint ← IO.ofExcept (Json.parse (← IO.FS.readFile "../onchain/plutus.json"))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  fieldEquals preamble "plutusVersion" "v3"
  let compiler ← IO.ofExcept (preamble.getObjVal? "compiler")
  fieldEquals compiler "name" "Aiken"
  fieldEquals compiler "version" "v1.1.22+39d6b04"
  let validators ← IO.ofExcept (blueprint.getObjValAs? (Array Json) "validators")
  let entries := validators.filter fun entry =>
    (entry.getObjValAs? String "title").toOption == some "settings.settings.mint"
  require (entries.size == 1) "Expected one Settings Mint blueprint entry"
  let entry := entries[0]!
  fieldEquals entry "hash" "2404b296676c4ab96a657c873a5bf58d01c77c6021f380a481a9a0bd"
  let declarations ← IO.ofExcept (entry.getObjValAs? (Array Json) "parameters")
  let names ← declarations.mapM fun p => IO.ofExcept (p.getObjValAs? String "title")
  require (names == #["seed_utxo", "propose_auth", "apply_auth", "apply_delay", "settings_token_name"])
    "Blueprint parameter declaration order changed"
  let schemas ← declarations.mapM fun p => IO.ofExcept do
    let schema ← p.getObjVal? "schema"
    schema.getObjValAs? String "$ref"
  require (schemas == #["#/definitions/cardano~1transaction~1OutputReference",
    "#/definitions/cardano~1address~1Credential", "#/definitions/cardano~1address~1Credential",
    "#/definitions/Int", "#/definitions/cardano~1assets~1AssetName"])
    "Blueprint parameter schema declarations changed"
  let code ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
  require (toHex (sha2_256 (← fromHex code)) ==
    "d3cdb83bc4248cb59f2681e47c46aeb7f0da2be0621f80f6adb2d4e1e566250f")
    "Unparameterized blueprint artifact changed"
  let .Program version body ← decodeProgram code
  let expected := Program.Program version
    (dataParameters.foldl (fun term parameter => .Apply term (.Const (.Data parameter))) body)
  require (reprStr applied == reprStr expected)
    "Applied program does not contain exactly the recorded blueprint and parameters"
  IO.println "UP016_ARTIFACT_AND_PARAMETERS_MATCH"

end Tests.UP016.VerifyArtifact

def main : IO Unit := Tests.UP016.VerifyArtifact.check

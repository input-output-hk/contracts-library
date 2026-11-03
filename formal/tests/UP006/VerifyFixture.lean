import Lean.Data.Json
import PlutusCore.Crypto.Hash
import tests.UP006.Fixture

open PlutusCore.UPLC.ScriptEncoding.Internal

def schemaKeys : List String := ["vesting/types/VestingDatum", "cardano/address/Credential", "aiken/crypto/VerificationKeyHash", "aiken/crypto/ScriptHash", "List<vesting/types/VestedAsset>", "vesting/types/VestedAsset", "cardano/assets/PolicyId", "cardano/assets/AssetName", "Int"]

def schemaSnapshot : String := "{\"schema\":{\"$ref\":\"#/definitions/vesting~1types~1VestingDatum\"},\"definitions\":{\"vesting/types/VestingDatum\":{\"title\":\"VestingDatum\",\"description\":\"Immutable vesting state. Written once at lock time; every continuing output\\n must reproduce it verbatim. Times are POSIX **milliseconds**.\",\"anyOf\":[{\"title\":\"VestingDatum\",\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"title\":\"beneficiary\",\"description\":\"Who may claim. A key authorizes by signing; a script by being invoked.\",\"$ref\":\"#/definitions/cardano~1address~1Credential\"},{\"title\":\"locker\",\"description\":\"Who may recover the remainder after `recovery_time`. Same pluggable\\n credential mechanism as `beneficiary`.\",\"$ref\":\"#/definitions/cardano~1address~1Credential\"},{\"title\":\"vesting\",\"description\":\"The original locked bundle and per-asset totals.\",\"$ref\":\"#/definitions/List<vesting~1types~1VestedAsset>\"},{\"title\":\"start_time\",\"$ref\":\"#/definitions/Int\"},{\"title\":\"end_time\",\"$ref\":\"#/definitions/Int\"},{\"title\":\"recovery_time\",\"description\":\"After this time the `locker` may recover whatever remains. Must be\\n strictly after `end_time` (enforced on cancel).\",\"$ref\":\"#/definitions/Int\"}]}]},\"cardano/address/Credential\":{\"title\":\"Credential\",\"description\":\"A general structure for representing an on-chain `Credential`.\\n\\n Credentials are always one of two kinds: a direct public/private key\\n pair, or a script (native or Plutus).\",\"anyOf\":[{\"title\":\"VerificationKey\",\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"$ref\":\"#/definitions/aiken~1crypto~1VerificationKeyHash\"}]},{\"title\":\"Script\",\"dataType\":\"constructor\",\"index\":1,\"fields\":[{\"$ref\":\"#/definitions/aiken~1crypto~1ScriptHash\"}]}]},\"aiken/crypto/VerificationKeyHash\":{\"title\":\"VerificationKeyHash\",\"dataType\":\"bytes\"},\"aiken/crypto/ScriptHash\":{\"title\":\"ScriptHash\",\"dataType\":\"bytes\"},\"List<vesting/types/VestedAsset>\":{\"dataType\":\"list\",\"items\":{\"$ref\":\"#/definitions/vesting~1types~1VestedAsset\"}},\"vesting/types/VestedAsset\":{\"title\":\"VestedAsset\",\"description\":\"One asset in a vesting bundle, paired with the **original** total quantity\\n that the schedule releases over its lifetime.\",\"anyOf\":[{\"title\":\"VestedAsset\",\"dataType\":\"constructor\",\"index\":0,\"fields\":[{\"title\":\"policy\",\"$ref\":\"#/definitions/cardano~1assets~1PolicyId\"},{\"title\":\"name\",\"$ref\":\"#/definitions/cardano~1assets~1AssetName\"},{\"title\":\"total\",\"$ref\":\"#/definitions/Int\"}]}]},\"cardano/assets/PolicyId\":{\"title\":\"PolicyId\",\"dataType\":\"bytes\"},\"cardano/assets/AssetName\":{\"title\":\"AssetName\",\"dataType\":\"bytes\"},\"Int\":{\"dataType\":\"integer\"}}}"

/-- Verify the fixed program and every transitive datum-schema definition. -/
def main : IO Unit := do
  let path := "../onchain/plutus.json"
  let blueprint ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  let version ← IO.ofExcept (preamble.getObjValAs? String "plutusVersion")
  unless version == "v3" do throw (IO.userError "UP006 requires Plutus V3")
  let validators ← IO.ofExcept do (← blueprint.getObjVal? "validators").getArr?
  let entries := validators.filter fun entry =>
    ((entry.getObjValAs? String "title").toOption.getD "").startsWith
      "linear_vesting.linear_vesting."
  let titles ← entries.mapM fun entry => IO.ofExcept (entry.getObjValAs? String "title")
  unless entries.size == 2 && titles.contains "linear_vesting.linear_vesting.spend" &&
      titles.contains "linear_vesting.linear_vesting.else" do
    throw (IO.userError "UP006 fixture handler declarations changed")
  let definitions ← IO.ofExcept (blueprint.getObjVal? "definitions")
  let expectedSchema ← IO.ofExcept (Lean.Json.parse schemaSnapshot)
  for entry in entries do
    let title ← IO.ofExcept (entry.getObjValAs? String "title")
    if title.endsWith ".spend" then
      let schema ← IO.ofExcept do (← entry.getObjVal? "datum").getObjVal? "schema"
      let fields ← schemaKeys.mapM fun key => do
        pure (key, ← IO.ofExcept (definitions.getObjVal? key))
      let actualSchema := Lean.Json.mkObj [("schema", schema), ("definitions", Lean.Json.mkObj fields)]
      unless actualSchema == expectedSchema do
        throw (IO.userError "UP006 datum schema differs from the frozen decoder snapshot")
    let code ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
    let hash ← IO.ofExcept (entry.getObjValAs? String "hash")
    unless code == UP006.compiledCode && hash == UP006.scriptHashHex do
      throw (IO.userError "UP006 fixture differs from the tracked blueprint")
    let decoded ← IO.ofExcept (singleCborEncodedScriptFromHex? code)
    unless reprStr decoded == reprStr UP006.program do
      throw (IO.userError "UP006 proof program differs from the tracked artifact")
    let some codeBytes := hexStringToString code.toList []
      | throw (IO.userError "UP006 compiledCode is not hexadecimal")
    unless codeBytes.length == 1404 do
      throw (IO.userError "UP006 compiledCode length changed")
    let scriptBytes : PlutusCore.ByteString.ByteString :=
      ⟨String.mk (Char.ofNat 3 :: codeBytes)⟩
    let computedHash := PlutusCore.Crypto.Hash.blake2b_224 scriptBytes
    unless computedHash == UP006.returnDatumScriptHash && reprStr computedHash == "#" ++ hash do
      throw (IO.userError "UP006 script hash does not bind the frozen program")
    if let .ok parameters := entry.getObjVal? "parameters" then
      let parameters ← IO.ofExcept parameters.getArr?
      unless parameters.isEmpty do
        throw (IO.userError "UP006 fixture does not support unapplied parameters")
  IO.println "UP006 blueprint, schema, 1404-byte program, and Plutus V3 hash match."

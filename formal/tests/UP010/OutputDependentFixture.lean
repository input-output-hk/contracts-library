import Lean.Data.Json
import Formal.Support.CandidateHelpers
import Formal.Vesting.Linear.Blueprint.Types

namespace Tests.UP010.OutputDependentFixture

open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)

/-!
Synthetic Plutus V3 negative control compiled from Project/validators/output_dependent.ak
with Aiken v1.1.21+42babe5 and stdlib v3.1.0. The 167-byte compiled artifact has
SHA-256 d845e54cb0be6203b5fd52c3e37d043f7cc41564502197fa98e3842932de9a75.
SourceCheck.lean checks the embedded program against the tracked Inputs/control.json.
RebuildCheck.lean optionally checks a fresh build of the isolated Aiken project.
-/

def compiledCode : String := "58a501010029800aba2aba1aab9faab9eaab9dab9a48888896600264646644b30013370e900118031baa0018994c004c028006601460160032259800800c5284566002b30013370e900118049baa300c300a3754601860146ea8c030006294629410084528c4cc008008c03400500820164888cc004004dd618069807180718059baa300d00818039baa0018b200a30070013007300800130070013003375400f149a26cac8009"

def program : Program := singleCborEncodedScriptFromHexM "58a501010029800aba2aba1aab9faab9eaab9dab9a48888896600264646644b30013370e900118031baa0018994c004c028006601460160032259800800c5284566002b30013370e900118049baa300c300a3754601860146ea8c030006294629410084528c4cc008008c03400500820164888cc004004dd618069807180718059baa300d00818039baa0018b200a30070013007300800130070013003375400f149a26cac8009"

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Support.rejectedWithin program [toTerm ctx] fuel

/-- Check both dispatched entries, the compiler, version, and absence of parameters. -/
private def checkBlueprint (path entryPrefix compilerVersion expectedHash : String)
    (expectedProgram : Program) (expectedCode : Option String := none) : IO Unit := do
  let blueprint ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let preamble ← IO.ofExcept (blueprint.getObjVal? "preamble")
  let version ← IO.ofExcept (preamble.getObjValAs? String "plutusVersion")
  let compiler ← IO.ofExcept (preamble.getObjVal? "compiler")
  let compilerName ← IO.ofExcept (compiler.getObjValAs? String "name")
  let actualCompiler ← IO.ofExcept (compiler.getObjValAs? String "version")
  unless version == "v3" && compilerName == "Aiken" && actualCompiler == compilerVersion do
    throw (IO.userError s!"{path}: unexpected Plutus version or compiler")
  let validators ← IO.ofExcept do (← blueprint.getObjVal? "validators").getArr?
  let entries := validators.filter fun entry =>
    ((entry.getObjValAs? String "title").toOption.getD "").startsWith entryPrefix
  let titles ← entries.mapM fun entry => IO.ofExcept (entry.getObjValAs? String "title")
  unless entries.size == 2 && titles.contains (entryPrefix ++ "spend") &&
      titles.contains (entryPrefix ++ "else") do
    throw (IO.userError s!"{path}: unexpected validator handlers")
  for entry in entries do
    let code ← IO.ofExcept (entry.getObjValAs? String "compiledCode")
    let hash ← IO.ofExcept (entry.getObjValAs? String "hash")
    unless hash == expectedHash do
      throw (IO.userError s!"{path}: unexpected declared script hash")
    if let some expected := expectedCode then
      unless code == expected do
        throw (IO.userError s!"{path}: compiled bytes differ from the frozen fixture")
    let decoded ← IO.ofExcept
      (PlutusCore.UPLC.ScriptEncoding.Internal.singleCborEncodedScriptFromHex? code)
    unless reprStr decoded == reprStr expectedProgram do
      throw (IO.userError s!"{path}: decoded program differs from the checked program")
    if let .ok parameters := entry.getObjVal? "parameters" then
      let parameters ← IO.ofExcept parameters.getArr?
      unless parameters.isEmpty do
        throw (IO.userError s!"{path}: unexpected unapplied parameters")

/-- Check the tracked inputs from formal/ without rebuilding Aiken. -/
def checkSources : IO Unit := do
  checkBlueprint "tests/UP010/Inputs/control.json" "output_dependent.output_dependent."
    "v1.1.21+42babe5" "c988dd668151710cdb060a1509185ab5301a7ec151a7373dcbc00b2d"
    program (some compiledCode)
  checkBlueprint "../onchain/plutus.json" "linear_vesting.linear_vesting."
    "v1.1.22+39d6b04" Formal.Vesting.Linear.Blueprint.scriptHashHex
    Formal.Vesting.Linear.Blueprint.program
  IO.println "UP010 control bytes and vesting program match their tracked blueprints."

/-- Optional comparison after rebuilding Project with the recorded Aiken version. -/
def checkRebuild : IO Unit := do
  checkSources
  checkBlueprint "tests/UP010/Project/plutus.json" "output_dependent.output_dependent."
    "v1.1.21+42babe5" "c988dd668151710cdb060a1509185ab5301a7ec151a7373dcbc00b2d"
    program (some compiledCode)
  IO.println "UP010 rebuilt control bytes match the frozen fixture."

end Tests.UP010.OutputDependentFixture

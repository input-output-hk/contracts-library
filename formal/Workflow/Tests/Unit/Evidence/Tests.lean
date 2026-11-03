import Workflow.App.Main

open Lean Workflow

namespace Workflow.Tests.Unit.Evidence

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def jsonFile (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def directories : IO (Array System.FilePath) := do
  let root : System.FilePath := "output"
  if ← root.pathExists then return (← root.readDir).map (·.path)
  return #[]

private def emptyProvider : Generator.Provider := {
  id := "fixture"
  generate := fun target _ => .ok { targetName := target.name, modules := #[], jobs := #[] } }

private def resolve : Option String → IO (Except String Generator.Provider) :=
  fun _ => pure (.ok emptyProvider)

private structure Saved where
  directory : System.FilePath
  report : Json
  invocation : Json

private def runCase (args : List String)
    (resolver := resolve) : IO Saved := do
  let before ← directories
  let code ← Main.run resolver args
  check "control has the expected inconclusive outcome" (code == 2)
  let created := (← directories).filter (!before.contains ·)
  let [directory] := created.toList | throw (IO.userError "expected one fresh run directory")
  let report ← jsonFile (directory / "report.json")
  let invocation ← jsonFile (directory / "invocation.json")
  check "report retains its actual exit code" ((report.getObjVal? "exitCode").toOption == some (toJson (2 : Nat)))
  check "invocation retains the exact received argument array"
    ((invocation.getObjVal? "args").toOption == some (toJson args))
  check "invocation retains the effective working directory"
    ((invocation.getObjVal? "cwd").toOption == some (.str (← IO.currentDir).toString))
  check "preparation controls invent no execution manifest" (!(← (directory / "execution.json").pathExists))
  return { directory, report, invocation }

private def snapshot (saved : Saved) (source : String) : IO Unit := do
  check "the exact source used for validation is saved"
    ((← IO.FS.readFile (saved.directory / "input.json")) == source)

def run : IO Unit := do
  let originalCwd ← IO.currentDir
  let valid ← IO.FS.readFile "Workflow/Tests/UP001/Inputs/plutus.json"
  let invalidCode ← IO.FS.readFile "Workflow/Tests/UP001/Inputs/invalid-code.json"
  IO.FS.withTempDir fun temporary => do
    IO.Process.setCurrentDir temporary
    try
      let path : System.FilePath := "input with spaces.json"
      for source in ["{\ninvalid", ""] do
        IO.FS.writeFile path source
        let attempt ← Input.readWithSource path "vault.vault"
        check "input boundary retains malformed and empty readable sources"
          (attempt.1 == some source && attempt.2.toOption.isNone)
        let saved ← runCase [path.toString, "vault.vault"]
        snapshot saved source
        check "default settings are recorded after successful option parsing"
          ((saved.invocation.getObjVal? "timeoutMs").toOption == some (toJson (300000 : Nat)) &&
           (saved.invocation.getObjVal? "requestedCheck").toOption == some .null &&
           (saved.invocation.getObjVal? "resolvedCheck").toOption == some (.str "fixture"))

      IO.FS.writeFile path invalidCode
      let badCode ← runCase [path.toString, "invalid.invalid", "--check", "fixture", "--timeout-ms", "1234"]
      snapshot badCode invalidCode
      check "explicit settings and the absolute input path are retained"
        ((badCode.invocation.getObjVal? "inputPath").toOption == some (.str (temporary / path).toString) &&
         (badCode.invocation.getObjVal? "validator").toOption == some (.str "invalid.invalid") &&
         (badCode.invocation.getObjVal? "requestedCheck").toOption == some (.str "fixture") &&
         (badCode.invocation.getObjVal? "timeoutMs").toOption == some (toJson (1234 : Nat)))

      IO.FS.writeFile path valid
      let wrongSelector ← runCase [path.toString, "missing"]
      snapshot wrongSelector valid
      let missing ← runCase ["missing.json", "vault.vault"]
      check "unreadable input is not invented" (!(← (missing.directory / "input.json").pathExists))
      check "unavailable source still has an invocation path"
        ((missing.invocation.getObjVal? "inputPath").toOption == some (.str (temporary / "missing.json").toString))

      let unknown ← runCase [path.toString, "vault.vault", "--check", "unknown"]
        (fun _ => pure (.error "unsupported fixture selection"))
      snapshot unknown valid
      check "failed provider lookup does not invent a resolved property"
        ((unknown.invocation.getObjVal? "resolvedCheck").toOption == some .null)
      let generationError : Generator.Provider := { emptyProvider with
        generate := fun _ _ => .error ⟨.unsupported, "generation control"⟩ }
      let generation ← runCase [path.toString, "vault.vault"] (fun _ => pure (.ok generationError))
      snapshot generation valid
      let invalidPlan : Generator.Provider := { emptyProvider with
        generate := fun target _ => .ok {
          targetName := target.name
          modules := #[⟨"../Invalid", ""⟩]
          jobs := #[{
            propertyId := "fixture"
            name := "invalid"
            moduleName := "../Invalid"
            statement := "True"
            expected := .valid
            scope := "preparation control" }] } }
      let preparation ← runCase [path.toString, "vault.vault"] (fun _ => pure (.ok invalidPlan))
      snapshot preparation valid
      let absolute ← runCase [(temporary / path).toString, "vault.vault"]
      snapshot absolute valid
      check "absolute input paths are not prefixed twice"
        ((absolute.invocation.getObjVal? "inputPath").toOption == some (.str (temporary / path).toString))

      let original := "{\noriginal malformed source"
      IO.FS.writeFile path original
      let changed ← runCase [path.toString, "vault.vault"] (fun _ => do
        IO.FS.writeFile path "changed after the read"
        return .ok emptyProvider)
      snapshot changed original
      check "the provider callback really changed the source file"
        ((← IO.FS.readFile path) == "changed after the read")
      IO.FS.writeFile path original
      let precedence ← runCase [path.toString, "vault.vault"]
        (fun _ => pure (.error "provider control must not hide intake"))
      let .error expected := Input.parse original "vault.vault"
        | throw (IO.userError "expected malformed control input")
      check "input errors retain precedence over provider errors"
        ((precedence.report.getObjVal? "problems").toOption == some (.arr #[.str (toString expected)]))

      let calls ← IO.mkRef (0 : Nat)
      for args in [[path.toString, "vault.vault", "--timeout-ms", "0"], []] do
        let invalidOptions ← runCase args (fun _ => do
          calls.modify (· + 1)
          return .ok emptyProvider)
        check "argument errors retain no invented parsed settings"
          ((invalidOptions.invocation.getObjVal? "timeoutMs").toOption == some .null &&
           (invalidOptions.invocation.getObjVal? "resolvedCheck").toOption == some .null)
        check "argument errors do not pretend to read a source"
          (!(← (invalidOptions.directory / "input.json").pathExists))
      check "argument errors never resolve a provider" ((← calls.get) == 0)
    finally
      IO.Process.setCurrentDir originalCwd
  IO.println "Run-evidence checks passed."

end Workflow.Tests.Unit.Evidence

def main : IO Unit := Workflow.Tests.Unit.Evidence.run

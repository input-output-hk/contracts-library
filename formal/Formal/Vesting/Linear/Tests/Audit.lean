import Lean

namespace Formal.Vesting.Linear.Tests

open Lean Elab Command

structure TheoremAudit where
  name : String
  axioms : Array String
  status : String
  deriving ToJson, FromJson

structure ModuleAudit where
  moduleName : String
  theorems : Array TheoremAudit
  deriving ToJson, FromJson

/-- Keep the existing standard and Blaster trust boundary visible in each result. -/
def axiomStatus (axioms : Array Name) : String :=
  let allowed := #[`propext, `Classical.choice, `Quot.sound, `Blaster.Tactic.blasterProven]
  if axioms.any (fun name => name != `sorryAx && !allowed.contains name) then "ERROR"
  else if axioms.contains `sorryAx then "PENDING"
  else "PASS"

/-- Inspect every theorem owned by the requested imported module, including its dependencies. -/
def inspectModule (moduleName : Name) : CommandElabM ModuleAudit := do
  let env ← getEnv
  let some moduleIndex := env.getModuleIdx? moduleName
    | throwError "requested module was not imported: {moduleName}"
  let mut theorems : Array TheoremAudit := #[]
  for (name, info) in env.constants do
    if env.getModuleIdxFor? name == some moduleIndex then
      if let .thmInfo _ := info then
        let axioms ← collectAxioms name
        let status := axiomStatus axioms
        theorems := theorems.push {
          name := name.toString
          axioms := (axioms.map Name.toString).qsort (· < ·)
          status }
        logInfo m!"{status}: {name}; axioms: {axioms}"
  return {
    moduleName := moduleName.toString
    theorems := theorems.qsort (fun a b => a.name < b.name) }

def auditModule (moduleName : Name) (outputPath : String) : CommandElabM Unit := do
  let result ← inspectModule moduleName
  liftIO <| IO.FS.writeFile outputPath ((toJson result).pretty ++ "\n")

end Formal.Vesting.Linear.Tests

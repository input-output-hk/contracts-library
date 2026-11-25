import Lean
import Formal

open Lean Elab Command

private def checkAxioms (label : String) (decl : Name) : CommandElabM Unit := do
  let allowed := #[`propext, `Classical.choice, `Quot.sound, `Blaster.Tactic.blasterProven]
  let unexpected := (← collectAxioms decl).filter fun a => !allowed.contains a
  unless unexpected.isEmpty do throwError "{label}: {decl} depends on disallowed axioms {unexpected}"

-- Check the catalogue against the declarations in the compiled milestone.
run_cmd do
  let env ← getEnv
  unless (env.getModuleIdx? `Formal.LinearVesting).isSome do
    throwError "Formal must import the M1.2 milestone Formal.LinearVesting"
  let catalogue ← IO.ofExcept <| Json.parse (← IO.FS.readFile "Formal/LinearVesting/properties.json")
  let properties ← IO.ofExcept catalogue.getArr?
  if properties.isEmpty then throwError "M1.2 property catalogue is empty"
  let mut propertyIds : Std.HashSet String := {}
  let mut proofs : NameSet := {}
  for property in properties do
    let id ← IO.ofExcept (property.getObjValAs? String "id")
    if id.trim.isEmpty || propertyIds.contains id then throwError "invalid or duplicate property id: {id}"
    propertyIds := propertyIds.insert id
    let refs ← IO.ofExcept (property.getObjValAs? (Array String) "theorems")
    if refs.isEmpty then throwError "{id}: no theorem references"
    for ref in refs do
      let decl := ref.toName
      unless wasOriginallyTheorem env decl do
        throwError "{id}: {ref} is missing or is not a theorem"
      let some idx := env.getModuleIdxFor? decl | throwError "{id}: unknown module for {ref}"
      let modName := env.header.moduleNames[idx.toNat]!
      unless `Formal.LinearVesting |>.isPrefixOf modName do
        throwError "{id}: {ref} belongs to {modName}, outside the active milestone"
      if `Formal.LinearVesting.Old |>.isPrefixOf modName then
        throwError "{id}: {ref} belongs to the archived module {modName}"
      unless proofs.contains decl do
        checkAxioms id decl
        proofs := proofs.insert decl

  -- Check helpers and private/unlisted declarations in the project's build as well.
  for (name, info) in env.constants do
    if let some idx := env.getModuleIdxFor? name then
      let modName := env.header.moduleNames[idx.toNat]!
      if `Formal |>.isPrefixOf modName then
        if info.type.hasSorry || (info.value? true).any Expr.hasSorry then
          throwError "{modName}: declaration {name} contains sorryAx"
        if wasOriginallyTheorem env name && !proofs.contains name then
          checkAxioms modName.toString name
  logInfo m!"M1.2 proof audit passed ({properties.size} properties, {proofs.size} distinct theorems)."

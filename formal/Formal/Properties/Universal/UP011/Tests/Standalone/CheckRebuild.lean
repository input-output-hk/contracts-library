import Formal.Properties.Universal.UP011.Tests.Standalone.Fixture

-- Optional reproduction check after rebuilding Project with the recorded Aiken version.
#eval do
  Tests.UP011.Fixture.checkSource
  let frozen ← IO.ofExcept (Lean.Json.parse
    (← IO.FS.readFile "Formal/Properties/Universal/UP011/Tests/Standalone/Inputs/control.json"))
  let rebuilt ← IO.ofExcept (Lean.Json.parse
    (← IO.FS.readFile "Formal/Properties/Universal/UP011/Tests/Standalone/Project/plutus.json"))
  unless frozen == rebuilt do
    throw (IO.userError "UP011 rebuilt blueprint differs from the tracked fixture")
  IO.println "UP011 rebuilt blueprint matches the tracked fixture."

import tests.UP011.Fixture

-- Optional reproduction check after rebuilding Project with the recorded Aiken version.
#eval do
  Tests.UP011.Fixture.checkSource
  let frozen ← IO.ofExcept (Lean.Json.parse
    (← IO.FS.readFile "tests/UP011/Inputs/control.json"))
  let rebuilt ← IO.ofExcept (Lean.Json.parse
    (← IO.FS.readFile "tests/UP011/Project/plutus.json"))
  unless frozen == rebuilt do
    throw (IO.userError "UP011 rebuilt blueprint differs from the tracked fixture")
  IO.println "UP011 rebuilt blueprint matches the tracked fixture."

import Workflow.Preparation.Program
import Workflow.Input.Basic

namespace Workflow.Tests.Unit.Program

open Workflow

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"FAIL: {label}")

private def contains (source text : String) : Bool :=
  (source.splitOn text).length > 1

private def load (path selector : String) : IO TargetDescription := do
  return (← IO.ofExcept ((← Input.read path selector).mapError toString)).target

def run : IO Unit := do
  let vectors := [
    ("Workflow/Tests/UP001/Inputs/plutus.json", "vault.vault",
     "7ee33b926834bd7d983ca9d433cee0cc1918ed5bcb5f78ab795d7057"),
    ("Workflow/Tests/UP001/Inputs/plutus.json", "vault_buggy.vault_buggy",
     "5d0f747d4eb70739ff667eed99b934de3a3e5054fae1e368902078e3"),
    ("Workflow/Tests/UP012/Inputs/plutus.json", "linear_vesting.linear_vesting",
     "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a"),
    ("Workflow/Tests/Profiles/Inputs/linear-vesting-aiken-1.1.21.json",
     "linear_vesting.linear_vesting", "114e35c85d59745cb61ba73e1a9192467a4dae666a286a45f97a15f8")]
  let mut identities : Array String := #[]
  for (path, selector, expectedHash) in vectors do
    let target ← load path selector
    let hash ← IO.ofExcept (Preparation.Program.scriptHashHex target.compiledCode)
    check s!"{selector}: independently fixed Cardano V3 hash vector" (hash == expectedHash)
    identities := identities.push hash
    let prepared ← IO.ofExcept (Preparation.Program.support target "Generated.Actual")
    check "selected bytes and computed hash appear in the generated program"
      (prepared.name == "Generated.Actual.Types" &&
       contains prepared.source s!"singleCborEncodedScriptFromHexM {reprStr target.compiledCode}" &&
       contains prepared.source s!"def scriptHashHex : String := {reprStr expectedHash}")
    let renamed := { target with
      name := "unsafe\nend Arbitrary"
      compiler := some (.str "-/ injected")
      handlers := target.handlers.map fun handler =>
        { handler with name := "different", declaredHash := some "wrong" } }
    let metadata ← IO.ofExcept (Preparation.Program.support renamed "Generated.Actual")
    check "names, compiler metadata, and declared hashes do not select executable content"
      (metadata.source == prepared.source)
    let uppercase ← IO.ofExcept (Preparation.Program.support
      { target with compiledCode := target.compiledCode.toUpper } "Generated.Actual")
    check "uppercase hexadecimal canonicalizes without changing bytes"
      (uppercase.source == prepared.source)
    let alias ← IO.ofExcept (Preparation.Program.support target "Other.Target")
    check "module aliases preserve every compiled byte and hash"
      (alias.name == "Other.Target.Types" &&
       alias.source == prepared.source.replace "Generated.Actual" "Other.Target")
    check "explicit empty parameters are admitted"
      (Preparation.Program.support { target with parameters := some #[] } "Generated.Actual").isOk
    for code in ["", "zz", "0", "40", "4100", "49010000222120010100", target.compiledCode ++ "00"] do
      check "direct preparation rejects malformed hex, CBOR, UPLC, and trailing CBOR bytes"
        (!(Preparation.Program.support { target with compiledCode := code } "Generated.Actual").isOk)
    for moduleName in ["", "lowercase", "Generated..Target", "Generated.Target\nend Generated", "Type"] do
      check "module prefix cannot inject Lean code"
        (!(Preparation.Program.support target moduleName).isOk)
    check "other Plutus versions are rejected"
      (!(Preparation.Program.support { target with plutusVersion := "v2" } "Generated.Actual").isOk)
    let parameter : ArgumentDescription := { schema := .null, title := none, description := none }
    check "unapplied parameters are rejected"
      (!(Preparation.Program.support { target with parameters := some #[parameter] }
        "Generated.Actual").isOk)
  let base ← load "Workflow/Tests/UP001/Inputs/plutus.json" "vault.vault"
  let novel := { base with compiledCode := "480100002221200101" }
  let preparedNovel ← IO.ofExcept (Preparation.Program.support novel "Generated.Novel")
  check "valid code outside the historical fixture allowlist is prepared from its own bytes"
    (contains preparedNovel.source "480100002221200101" &&
     contains preparedNovel.source "6913eb6a46b67bfa1ca082f2b410b0a4e502237d03f7a0b7cbf1b025")
  check "different supplied programs have different computed identities"
    (identities.toList.eraseDups.length == 4)
  IO.println "Actual-program preparation checks passed."

end Workflow.Tests.Unit.Program

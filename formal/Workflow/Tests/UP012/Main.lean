import Workflow.Tests.Support
import Workflow.Tests.UP012.Tests
import Workflow.Tests.UP012.NegativeControl
import Workflow.Tests.UP012.VaultTests
import Workflow.Tests.UP012.ReusableTests

open Workflow.Tests.Support

def main (args : List String) : IO Unit := do
  Workflow.Tests.UP012.Tests.run
  if args == ["--unit"] then
    Workflow.Tests.UP012.VaultTests.runUnit
    Workflow.Tests.UP012.ReusableTests.runUnit
    return ()
  let passing ← invoke "Workflow/Tests/UP012/Inputs/plutus.json" "linear_vesting.linear_vesting"
    (some "UP-012") 300000
    "UP012: original vesting suite" "PASS/0; four Valid results, including both applicability obligations"
  expectOutcome "original UP012 vesting suite" passing "PASS" 0
  expectPropertyDefinition "original UP012 vesting suite" passing "UP-012" 1 "Formal.Properties.Universal.UP012.statement"
  expectRows "original UP012 vesting suite" passing 4 "UP-012" "PASS" "valid" "1,000,000-step bound"
  expectBindings "original UP012 vesting suite" passing "UP-012" 1 #[
    ("dropSigner_claim", "TxM-007"), ("dropSigner_claim_applies", "TxM-007"),
    ("dropSigner_cancel", "TxM-008"), ("dropSigner_cancel_applies", "TxM-008")]
  expectArtifacts "original UP012 vesting suite" passing #["Types.lean", "Tx.lean", "Checks.lean"]
  let checks ← rows passing.report
  let names ← checks.mapM (fun row => stringField row "name")
  check "UP012 preserves both property and applicability obligations"
    (names == #["dropSigner_claim", "dropSigner_claim_applies", "dropSigner_cancel", "dropSigner_cancel_applies"])
  let unsupported ← invoke "Workflow/Tests/UP012/Inputs/unsupported.json" "unsupported.validator"
    (some "UP-012") 300000
    "UP012: unsupported artifact" "INCONCLUSIVE/2; profile rejection (intentional unsupported case)"
  expectOutcome "unsupported UP012 artifact" unsupported "INCONCLUSIVE" 2
  expectPropertyDefinition "unsupported UP012 artifact" unsupported "UP-012" 1 "Formal.Properties.Universal.UP012.statement"
  check "unsupported profile has no proof observations" ((← rows unsupported.report).isEmpty)
  check "unsupported profile has no execution manifest"
    (!(← (unsupported.directory / "execution.json").pathExists))
  expectProblem "UP012 rejects unsupported profile" unsupported "original unparameterized"
  check "UP012 attempts have separate output directories" (passing.directory != unsupported.directory)
  Workflow.Tests.UP012.NegativeControl.run
  Workflow.Tests.UP012.VaultTests.run
  Workflow.Tests.UP012.ReusableTests.run
  IO.println "UP012 whole-workflow checks passed."

import Formal.Properties.Universal.UP014.Run
import Formal.TxModels.Definitions.TxM007
import Workflow.Declarative.Catalogue
import Workflow.Input

namespace Workflow.Tests.UP014.Fixture

open Workflow Workflow.Declarative

def blueprint := "Workflow/Tests/UP012/Inputs/plutus.json"

def selector := "linear_vesting.linear_vesting"

def selection : Array CheckId := #[
  { propertyId := "UP-014", definitionVersion := 1, modelId := "TxM-007" }]

def catalogue : IO Catalogue := do
  IO.ofExcept (← Catalogue.load #[{
    run := Formal.Properties.Universal.UP014.run
    runModule := "Formal.Properties.Universal.UP014.Run"
    definitionModule := "Formal.Properties.Universal.UP014.Definition"
    metadataPath := "Formal/Properties/Universal/UP014/metadata.json" }] #[
    { moduleName := "Formal.TxModels.Definitions.TxM007"
      runnable := Formal.TxModels.TxM007.runnable }])

def input : IO InputResult := do
  IO.ofExcept ((← Input.read blueprint selector).mapError toString)

end Workflow.Tests.UP014.Fixture

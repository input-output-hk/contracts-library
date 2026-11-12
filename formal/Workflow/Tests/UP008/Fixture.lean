import Formal.Properties.Universal.UP008.Run
import Formal.TxModels.Definitions.TxM007
import Workflow.Declarative.Catalogue
import Workflow.Input

namespace Workflow.Tests.UP008.Fixture

open Workflow Workflow.Declarative

def blueprint := "Workflow/Tests/UP012/Inputs/plutus.json"

def selector := "linear_vesting.linear_vesting"

def selection : Array CheckId := #[
  { propertyId := "UP-008", definitionVersion := 1, modelId := "TxM-007" }]

def catalogue : IO Catalogue := do
  IO.ofExcept (← Catalogue.load #[{
    run := Formal.Properties.Universal.UP008.run
    runModule := "Formal.Properties.Universal.UP008.Run"
    definitionModule := "Formal.Properties.Universal.UP008.Definition"
    metadataPath := "Formal/Properties/Universal/UP008/metadata.json" }] #[
    { moduleName := "Formal.TxModels.Definitions.TxM007"
      runnable := Formal.TxModels.TxM007.runnable }])

def input : IO InputResult := do
  IO.ofExcept ((← Input.read blueprint selector).mapError toString)

end Workflow.Tests.UP008.Fixture

import Formal.Properties.Universal.UP000.Run
import Formal.TxModels.Definitions.TxM007
import Formal.TxModels.Definitions.TxM008
import Workflow.Declarative.Catalogue
import Workflow.Input

namespace Workflow.Tests.UP000.Fixture

open Workflow Workflow.Declarative

def blueprint := "Workflow/Tests/UP012/Inputs/plutus.json"

def selector := "linear_vesting.linear_vesting"

def selection : Array CheckId := #[
  { propertyId := "UP-000", definitionVersion := 1, modelId := "TxM-007" },
  { propertyId := "UP-000", definitionVersion := 1, modelId := "TxM-008" }]

def catalogue : IO Catalogue := do
  IO.ofExcept (← Catalogue.load #[{
    run := Formal.Properties.Universal.UP000.run
    runModule := "Formal.Properties.Universal.UP000.Run"
    definitionModule := "Formal.Properties.Universal.UP000.Definition"
    metadataPath := "Formal/Properties/Universal/UP000/metadata.json" }] #[
    { moduleName := "Formal.TxModels.Definitions.TxM007"
      runnable := Formal.TxModels.TxM007.runnable },
    { moduleName := "Formal.TxModels.Definitions.TxM008"
      runnable := Formal.TxModels.TxM008.runnable }])

def input : IO InputResult := do
  IO.ofExcept ((← Input.read blueprint selector).mapError toString)

end Workflow.Tests.UP000.Fixture

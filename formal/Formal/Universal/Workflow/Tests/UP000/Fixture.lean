import Formal.Universal.Properties.UP000.Run
import Formal.Universal.TxModels.Definitions.TxM007
import Formal.Universal.TxModels.Definitions.TxM008
import Formal.Universal.Workflow.Declarative.Catalogue
import Formal.Universal.Workflow.Input

namespace Formal.Universal.Workflow.Tests.UP000.Fixture

open Formal.Universal.Workflow Formal.Universal.Workflow.Declarative

def blueprint := "Formal/Universal/Workflow/Tests/UP012/Inputs/plutus.json"

def selector := "linear_vesting.linear_vesting"

def selection : Array CheckId := #[
  { propertyId := "UP-000", definitionVersion := 1, modelId := "TxM-007" },
  { propertyId := "UP-000", definitionVersion := 1, modelId := "TxM-008" }]

def catalogue : IO Catalogue := do
  IO.ofExcept (← Catalogue.load #[{
    run := Formal.Universal.Properties.UP000.run
    runModule := "Formal.Universal.Properties.UP000.Run"
    definitionModule := "Formal.Universal.Properties.UP000.Definition"
    metadataPath := "Formal/Universal/Properties/UP000/metadata.json" }] #[
    { moduleName := "Formal.Universal.TxModels.Definitions.TxM007"
      runnable := Formal.Universal.TxModels.TxM007.runnable },
    { moduleName := "Formal.Universal.TxModels.Definitions.TxM008"
      runnable := Formal.Universal.TxModels.TxM008.runnable }])

def input : IO InputResult := do
  IO.ofExcept ((← Input.read blueprint selector).mapError toString)

end Formal.Universal.Workflow.Tests.UP000.Fixture

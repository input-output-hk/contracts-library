import Formal.Universal.Properties.UP011.Run
import Formal.Universal.TxModels.Definitions.TxM007
import Formal.Universal.Workflow.Declarative.Catalogue
import Formal.Universal.Workflow.Input

namespace Formal.Universal.Workflow.Tests.UP011.Fixture

open Formal.Universal.Workflow Formal.Universal.Workflow.Declarative

def blueprint := "Formal/Universal/Workflow/Tests/UP012/Inputs/plutus.json"

def selector := "linear_vesting.linear_vesting"

def selection : Array CheckId := #[
  { propertyId := "UP-011", definitionVersion := 1, modelId := "TxM-007" }]

def catalogue : IO Catalogue := do
  IO.ofExcept (← Catalogue.load #[{
    run := Formal.Universal.Properties.UP011.run
    runModule := "Formal.Universal.Properties.UP011.Run"
    definitionModule := "Formal.Universal.Properties.UP011.Definition"
    metadataPath := "Formal/Universal/Properties/UP011/metadata.json" }] #[
    { moduleName := "Formal.Universal.TxModels.Definitions.TxM007"
      runnable := Formal.Universal.TxModels.TxM007.runnable }])

def input : IO InputResult := do
  IO.ofExcept ((← Input.read blueprint selector).mapError toString)

end Formal.Universal.Workflow.Tests.UP011.Fixture

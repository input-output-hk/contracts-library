import Formal.Universal.Standalone.Settings.MintQuantity

-- Retain all seventeen original assertions and their original fuel.
def main : IO Unit :=
  Formal.Universal.Standalone.Settings.runConcreteControls
    Formal.Universal.Standalone.Settings.probe Formal.Universal.Support.ledgerFuel

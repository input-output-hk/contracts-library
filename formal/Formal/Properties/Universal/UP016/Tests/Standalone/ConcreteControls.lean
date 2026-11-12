import Formal.Settings.Blueprint.MintQuantity

-- Retain all seventeen original assertions and their original fuel.
def main : IO Unit :=
  Formal.Settings.Blueprint.runConcreteControls
    Formal.Settings.Blueprint.probe Formal.Support.ledgerFuel

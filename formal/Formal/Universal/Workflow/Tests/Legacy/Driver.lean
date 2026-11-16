import Formal.Universal.Workflow.Tests.Legacy.Main
import Formal.Universal.Workflow.Tests.Legacy.Candidates.Catalogue

def main (args : List String) : IO UInt32 :=
  Formal.Universal.Workflow.Tests.Legacy.Main.run Formal.Universal.Workflow.Tests.Legacy.Candidates.Catalogue.loadProvider args

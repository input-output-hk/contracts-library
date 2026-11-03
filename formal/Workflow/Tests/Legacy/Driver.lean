import Workflow.Tests.Legacy.Main
import Workflow.Tests.Legacy.Candidates.Catalogue

def main (args : List String) : IO UInt32 :=
  Workflow.Tests.Legacy.Main.run Workflow.Tests.Legacy.Candidates.Catalogue.loadProvider args

import Formal.Universal.Workflow.Tests.Unit.Compatibility.Tests
import Formal.Universal.Workflow.Tests.Unit.Program.Tests

def main : IO Unit := do
  Formal.Universal.Workflow.Tests.Unit.Compatibility.run
  Formal.Universal.Workflow.Tests.Unit.Program.run

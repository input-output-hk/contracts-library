import Workflow.Tests.Unit.Compatibility.Tests
import Workflow.Tests.Unit.Program.Tests

def main : IO Unit := do
  Workflow.Tests.Unit.Compatibility.run
  Workflow.Tests.Unit.Program.run

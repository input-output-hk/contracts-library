import Workflow.Tests.SingleCheck.Tests

def main (args : List String) : IO UInt32 := do
  if args == ["--version"] then
    IO.println "Controlled single-check compiler fixture"
    return 0
  if args == ["--unit"] then
    Workflow.Tests.SingleCheck.runUnit
    return 0
  if args.contains "--json" then Workflow.Tests.SingleCheck.compiler args
  else
    Workflow.Tests.SingleCheck.run
    return 0

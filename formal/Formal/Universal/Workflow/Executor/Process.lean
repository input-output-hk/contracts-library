import Formal.Universal.Workflow.Executor.Types

namespace Formal.Universal.Workflow.Executor.Process

/-- Run the executor command through the shared process runner. -/
def run (options : Options) (deadline : Nat) (args : Array String)
    (environment : Array (String × Option String)) : IO ProcessObservation :=
  Formal.Shared.Process.run {
    command := options.leanCommand
    timeoutCommand := options.timeoutCommand
    workingDirectory := options.workingDirectory }
    deadline args environment

end Formal.Universal.Workflow.Executor.Process

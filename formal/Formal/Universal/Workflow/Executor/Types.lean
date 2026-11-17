import Formal.Shared.Process
import Formal.Universal.Workflow.Types.Jobs

namespace Formal.Universal.Workflow.Executor

abbrev ProcessState := Formal.Shared.Process.ProcessState
abbrev Invocation := Formal.Shared.Process.Invocation
abbrev ProcessObservation := Formal.Shared.Process.ProcessObservation

namespace ProcessState
export Formal.Shared.Process.ProcessState (finished timedOut launchError)
end ProcessState

namespace Invocation
export Formal.Shared.Process.Invocation (mk)
abbrev command (invocation : Invocation) : String :=
  Formal.Shared.Process.Invocation.command invocation
abbrev args (invocation : Invocation) : Array String :=
  Formal.Shared.Process.Invocation.args invocation
abbrev cwd (invocation : Invocation) : System.FilePath :=
  Formal.Shared.Process.Invocation.cwd invocation
abbrev environment (invocation : Invocation) : Array (String × Option String) :=
  Formal.Shared.Process.Invocation.environment invocation
abbrev toJson (invocation : Invocation) : Lean.Json :=
  Formal.Shared.Process.Invocation.toJson invocation
end Invocation

namespace ProcessObservation
export Formal.Shared.Process.ProcessObservation (mk)
abbrev state (observation : ProcessObservation) : ProcessState :=
  Formal.Shared.Process.ProcessObservation.state observation
abbrev exitCode (observation : ProcessObservation) : Option UInt32 :=
  Formal.Shared.Process.ProcessObservation.exitCode observation
abbrev stdout (observation : ProcessObservation) : String :=
  Formal.Shared.Process.ProcessObservation.stdout observation
abbrev stderr (observation : ProcessObservation) : String :=
  Formal.Shared.Process.ProcessObservation.stderr observation
abbrev elapsedMs (observation : ProcessObservation) : Nat :=
  Formal.Shared.Process.ProcessObservation.elapsedMs observation
abbrev invocation (observation : ProcessObservation) : Option Invocation :=
  Formal.Shared.Process.ProcessObservation.invocation observation
end ProcessObservation

structure Diagnostic where
  fileName : String
  line : Nat
  column : Nat
  severity : String
  message : String

inductive ObservedResult where
  | valid | falsified | inconclusive
  deriving BEq, Repr

structure JobObservation where
  job : CheckJob
  observed : ObservedResult := .inconclusive
  /-- The module finished with intact evidence; local job issues remain separate. -/
  evidenceComplete : Bool := false
  diagnostics : Array Diagnostic := #[]
  issues : Array String := #[]

structure ModuleObservation where
  name : String
  path : System.FilePath
  process : ProcessObservation

inductive RunState where
  | completed | timedOut | error | noObligations
  deriving BEq, Repr

structure Result where
  state : RunState
  /-- Search path actually used after optional shared import preparation. -/
  leanPath : Option String := none
  directory : Option System.FilePath := none
  modules : Array ModuleObservation := #[]
  jobs : Array JobObservation := #[]
  problems : Array String := #[]
  /-- File retention failures, separate from inconclusive verification outcomes. -/
  retentionErrors : Array String := #[]
  elapsedMs : Nat := 0
  propertyDefinition : Option PropertyDefinition := none

structure Options where
  /-- Prepared dependency/module search path; preparation is the caller's responsibility. -/
  leanPath : String
  /-- Optional shared import preparation after source retention, before the proof budget. -/
  prepareImports : Option (GenerationPlan → IO String) := none
  leanCommand : String := "lean"
  timeoutCommand : String := "timeout"
  /-- Override the child working directory without mutating the parent process. -/
  workingDirectory : Option System.FilePath := none
  /-- Parent for fresh run directories; none uses the system temporary directory. -/
  outputRoot : Option System.FilePath := none
  /-- An existing empty workspace reserved by the coordinator, when supplied. -/
  directory : Option System.FilePath := none
  /-- One shared wall-clock budget across generated modules. -/
  budgetMs : Nat := 300000

end Formal.Universal.Workflow.Executor

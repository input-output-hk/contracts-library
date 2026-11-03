import Lean.Data.Json
import Workflow.Types.Jobs

namespace Workflow.Executor

inductive ProcessState where
  | finished | timedOut | launchError
  deriving BEq, Repr

/-- An attempted process invocation and its explicit environment overrides. -/
structure Invocation where
  command : String
  args : Array String
  cwd : System.FilePath
  environment : Array (String × Option String)

def Invocation.toJson (invocation : Invocation) : Lean.Json := Lean.Json.mkObj [
  ("command", .str invocation.command), ("args", Lean.toJson invocation.args),
  ("cwd", .str invocation.cwd.toString),
  ("environment", .arr (invocation.environment.map fun (name, value) => Lean.Json.mkObj [
    ("name", .str name), ("value", value.map Lean.Json.str |>.getD .null)]))]

structure ProcessObservation where
  state : ProcessState
  exitCode : Option UInt32 := none
  stdout : String := ""
  stderr : String := ""
  elapsedMs : Nat := 0
  invocation : Option Invocation := none

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
  /-- Parent for fresh run directories; none uses the system temporary directory. -/
  outputRoot : Option System.FilePath := none
  /-- An existing empty workspace reserved by the coordinator, when supplied. -/
  directory : Option System.FilePath := none
  /-- One shared wall-clock budget across generated modules. -/
  budgetMs : Nat := 300000

end Workflow.Executor

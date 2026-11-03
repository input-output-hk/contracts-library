import Lean.Data.Json

namespace Workflow

/-- The purposes supported by the first Plutus V3 input profile. -/
inductive Purpose where
  | spend | mint | withdraw | publish | vote | propose
  deriving BEq, Repr

def Purpose.name : Purpose → String
  | .spend => "spend"
  | .mint => "mint"
  | .withdraw => "withdraw"
  | .publish => "publish"
  | .vote => "vote"
  | .propose => "propose"

/-- Schema descriptions stay declarative; Input does not translate them to Lean types. -/
structure ArgumentDescription where
  schema : Lean.Json
  title : Option String
  description : Option String
  deriving BEq

structure HandlerDescription where
  name : String
  /-- `none` denotes the exported fallback handler, not a declared purpose. -/
  purpose : Option Purpose
  datum : Option ArgumentDescription
  redeemer : Option ArgumentDescription
  declaredHash : Option String
  deriving BEq

/-- Generator's input, separate from the blueprint document and its provenance. -/
structure TargetDescription where
  name : String
  plutusVersion : String
  compiledCode : String
  handlers : Array HandlerDescription
  /-- Preserve the distinction between absent parameters and an explicit empty list. -/
  parameters : Option (Array ArgumentDescription)
  /-- The first adapter preserves the shared schema vocabulary and definition registry. -/
  definitions : Option Lean.Json
  compiler : Option Lean.Json
  deriving BEq

def TargetDescription.declaredPurposes (target : TargetDescription) : Array Purpose :=
  target.handlers.filterMap (·.purpose)

/-- The coordinator can retain the exact source separately from Generator's input. -/
structure InputResult where
  target : TargetDescription
  sourceText : String
  sourcePath : Option System.FilePath

end Workflow

import Workflow.Metadata.TxModel

namespace Workflow

private def asciiLetter (c : Char) : Bool :=
  ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z')

private def moduleSegment (segment : String) : Bool :=
  match segment.data with
  | [] => false
  | first :: rest =>
    'A' ≤ first && first ≤ 'Z' &&
      rest.all (fun c => asciiLetter c || c.isDigit || c == '_') &&
      !["Type", "Prop", "Sort"].contains segment

/-- Module names accepted by generation and isolated artifact writing. -/
def validModuleName (name : String) : Bool :=
  (name.splitOn ".").all moduleSegment

inductive ExpectedResult where
  | valid | falsified
  deriving BEq, Repr

structure GeneratedModule where
  name : String
  source : String

inductive JobRole where
  | property | applicability
  deriving BEq, Repr

def JobRole.label : JobRole → String
  | .property => "property"
  | .applicability => "applicability"

/-- A reference to one obligation in the current generation plan. -/
structure JobRef where
  moduleName : String
  name : String
  deriving BEq, Repr

/-- A job declares its expectation; downstream code need not interpret property IDs. -/
structure CheckJob where
  propertyId : String
  name : String
  moduleName : String
  statement : String
  expected : ExpectedResult
  scope : String
  role : JobRole := .property
  applicability : Option JobRef := none
  /-- Model selected by registered construction code, independently of descriptions. -/
  txModelId : Option String := none
  binding : Option CheckBinding := none

inductive GenerationStatus where
  | ready | noObligations
  deriving BEq, Repr

structure GenerationPlan where
  targetName : String
  modules : Array GeneratedModule
  jobs : Array CheckJob
  notes : Array String := #[]
  status : GenerationStatus := .ready
  propertyDefinition : Option PropertyDefinition := none
  bindingsRequired : Bool := false

/-- Validate retained identities without using descriptions to choose executable code. -/
def GenerationPlan.validateBindings (plan : GenerationPlan) : Except String Unit := do
  for job in plan.jobs do
    match job.binding with
    | none =>
      if plan.bindingsRequired then throw s!"missing model binding for {job.name}"
    | some binding =>
      let some definition := plan.propertyDefinition
        | throw s!"model binding for {job.name} has no property definition"
      binding.validate job.propertyId definition
      unless job.txModelId == binding.combinedCheck.txModelId? do
        throw s!"model binding does not match the registered construction for {job.name}"
      for other in plan.jobs do
        if let some otherBinding := other.binding then
          if binding.txModel.id? == otherBinding.txModel.id? &&
              binding.txModel != otherBinding.txModel then
            throw "conflicting transaction-model snapshots for the same ID"
          if binding.combinedCheck.propertyId? == otherBinding.combinedCheck.propertyId? &&
              binding.combinedCheck.definitionVersion? == otherBinding.combinedCheck.definitionVersion? &&
              binding.combinedCheck.txModelId? == otherBinding.combinedCheck.txModelId? &&
              binding.combinedCheck != otherBinding.combinedCheck then
            throw "conflicting combined-check snapshots for the same property/model pair"

end Workflow

import Workflow.Executor.Types

namespace Workflow.Executor.Diagnostics

open Lean

structure DeclarationRange where
  name : String
  first : Nat
  last : Nat

def ranges (source : String) : Array DeclarationRange := Id.run do
  let lines := source.splitOn "\n" |>.toArray
  let mut starts : Array (String × Nat) := #[]
  for i in [:lines.size] do
    let line := lines[i]!
    if line.startsWith "theorem " || line.startsWith "def " then
      let token := (line.splitOn " ")[1]?.getD ""
      let name : String := ⟨token.data.takeWhile fun c => c != ':' && c != '('⟩
      starts := starts.push (name, i + 1)
  return starts.mapIdx fun i (name, first) =>
    { name, first, last := (starts[i + 1]?.map (·.2)).getD (lines.size + 1) - 1 }

private def decode (value : Json) : Option Diagnostic := do
  let text := fun key => (value.getObjVal? key).toOption.bind (·.getStr?.toOption)
  let pos ← (value.getObjVal? "pos").toOption
  return {
    fileName := ← text "fileName", severity := ← text "severity", message := ← text "data"
    line := ← (pos.getObjVal? "line").toOption.bind (·.getNat?.toOption)
    column := ← (pos.getObjVal? "column").toOption.bind (·.getNat?.toOption) }

def parse (output : String) : Array Diagnostic × Array String := Id.run do
  let mut diagnostics := #[]
  let mut problems := #[]
  for line in output.splitOn "\n" do
    let text := line.trim
    unless text.isEmpty do
      match Json.parse text with
      | .ok value =>
        match decode value with
        | some diagnostic => diagnostics := diagnostics.push diagnostic
        | none => problems := problems.push "unrecognized Lean JSON diagnostic"
      | .error _ =>
        if text.startsWith "{" || text.startsWith "error:" || text.startsWith "fatal error:" then
          problems := problems.push text
  return (diagnostics, problems)

private def valid (message : String) : Bool :=
  message == "✅ Valid" || message == "❌ Unexpected Valid" ||
    message.startsWith "declaration uses 'blasterProven'"

private def falsified (message : String) : Bool :=
  message == "❌ Falsified" || message == "✅ Expected Falsified"

private def uncertain (message : String) : Bool :=
  message.startsWith "declaration uses 'sorry'" ||
    message.startsWith "⚠️ Undetermined" || message == "✅ Expected Undetermined"

private def counterexampleDetail (diagnostic : Diagnostic) (others : Array Diagnostic) : Bool :=
  let samePosition := others.any fun other =>
    falsified other.message && other.line == diagnostic.line && other.column == diagnostic.column
  samePosition && (diagnostic.message == "Counterexample:" ||
    diagnostic.message.trim.startsWith "- " || diagnostic.message.startsWith
      "Tactic `blaster` failed: Goal was falsified (see counterexample above)")

private def sameFile (name : String) (path : System.FilePath) : Bool :=
  (System.FilePath.mk name).normalize == path.normalize

/-- Attribute only diagnostics from the job's file and declaration range. -/
def observe (source : GeneratedModule) (path : System.FilePath) (jobs : Array CheckJob)
    (process : ProcessObservation) : Array JobObservation × Array String := Id.run do
  let (diagnostics, initialProblems) := parse (process.stdout ++ "\n" ++ process.stderr)
  let declared := ranges source.source
  let mut problems := initialProblems
  let inJob := fun diagnostic => sameFile diagnostic.fileName path && jobs.any fun job =>
    declared.any fun range => range.name == job.name &&
      range.first ≤ diagnostic.line && diagnostic.line ≤ range.last
  for diagnostic in diagnostics do
    if !inJob diagnostic && (diagnostic.severity == "error" ||
        (sameFile diagnostic.fileName path && uncertain diagnostic.message)) then
      problems := problems.push s!"{diagnostic.fileName}:{diagnostic.line}: {diagnostic.message}"
  let errors := (diagnostics.filter (·.severity == "error")).size
  if process.state == .finished then
    match process.exitCode with
    | some 0 =>
      if errors != 0 then problems := problems.push "Lean exited successfully despite error diagnostics"
    | some 1 =>
      if errors == 0 then problems := problems.push "Lean failed without error diagnostics"
    | _ => problems := problems.push s!"unexpected compiler exit status: {reprStr process.exitCode}"
  else
    problems := problems.push (if process.state == .timedOut then "execution time budget exhausted"
      else s!"could not launch compiler: {process.stderr}")
  let evidenceComplete := process.state == .finished && problems.isEmpty
  let mut observations := #[]
  for job in jobs do
    let range := declared.find? (·.name == job.name)
    let relevant := diagnostics.filter fun diagnostic => sameFile diagnostic.fileName path &&
      (range.any fun r => r.first ≤ diagnostic.line && diagnostic.line ≤ r.last)
    let mut issues := #[]
    for diagnostic in relevant do
      if uncertain diagnostic.message || (diagnostic.severity == "error" &&
          !valid diagnostic.message && !falsified diagnostic.message &&
          !counterexampleDetail diagnostic relevant) then
        issues := issues.push diagnostic.message
    let sawValid := relevant.any (valid ∘ (·.message))
    let sawFalsified := relevant.any (falsified ∘ (·.message))
    if sawValid && sawFalsified then issues := issues.push "conflicting solver results"
    if !sawValid && !sawFalsified then issues := issues.push "no scoped solver result"
    let observed := if process.state != .finished || !problems.isEmpty || !issues.isEmpty then
      ObservedResult.inconclusive else if sawValid then .valid else .falsified
    observations := observations.push { job, observed, evidenceComplete, diagnostics := relevant, issues }
  return (observations, problems)

end Workflow.Executor.Diagnostics

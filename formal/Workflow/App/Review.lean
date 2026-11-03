import Workflow.App.Output

namespace Workflow.App.Review

private def markdown (text : String) : String :=
  String.join (text.toList.map fun c =>
    if c == '\n' || c == '\r' then " "
    else if "\\[]()`*_{}<>#!|".contains c then "\\" ++ c.toString
    else if c.toNat < 32 || c.toNat == 127 then " "
    else c.toString)

private def uri (path : System.FilePath) : String :=
  String.join (path.toString.toUTF8.toList.map fun byte =>
    let n := byte.toNat
    if (n >= 48 && n <= 57) || (n >= 65 && n <= 90) ||
        (n >= 97 && n <= 122) || "-._~/".contains (Char.ofNat n) then
      (Char.ofNat n).toString
    else
      let hex := "0123456789ABCDEF".toList.toArray
      "%" ++ hex[n / 16]!.toString ++ hex[n % 16]!.toString)

private def link (path : System.FilePath) : String :=
  s!"[{markdown path.toString}]({uri path})"

/-- Discover retained ordinary files without entering symbolic links. -/
private partial def files (root : System.FilePath) (relative : System.FilePath := "") :
    IO (Array System.FilePath) := do
  let path := root / relative
  let metadata ← path.symlinkMetadata
  if metadata.type == .file then return #[relative]
  if metadata.type != .dir then return #[]
  let entries ← path.readDir
  let mut found := #[]
  for entry in entries do
    let child := if relative.toString.isEmpty then System.FilePath.mk entry.fileName
      else relative / entry.fileName
    found := found ++ (← files root child)
  return found.qsort (fun a b => a.toString < b.toString)

private def under (directory path : System.FilePath) : Bool :=
  path.toString.startsWith (directory.toString ++ "/")

private def fileLines (paths : Array System.FilePath) : Array String :=
  paths.map (fun path => "- " ++ link path)

/-- Write a portable navigation page for the files retained at this checkpoint. -/
def write (run : RunRecord) : IO Unit := do
  let retained ← files run.directory
  let mut lines := #["# Run review", "",
    "Open the generated Lean below to review each selected property and model. " ++
      "Verdicts come from the recorded check results; their scope and reasons remain in those results.", ""]
  let snapshots := retained.filter fun path =>
    #["run.json", "input.json", "checks.json"].contains path.toString
  if !snapshots.isEmpty then
    lines := lines ++ #["## Run records", ""] ++ fileLines snapshots ++ #[""]
  if run.validators.isEmpty then
    lines := lines ++ #["No validator checks have been selected in this checkpoint.", ""]
  for validator in run.validators do
    lines := lines ++ #[s!"## {markdown validator.name}", ""]
    if let some message := validator.preparationError then
      lines := lines ++ #["Preparation error: " ++ markdown message, ""]
    if validator.checks.isEmpty then
      lines := lines ++ #["No checks selected for this validator.", ""]
    for check in validator.checks do
      let directory := checkDirectory validator.name check.id
      let checkFiles := retained.filter (under directory)
      let generated := checkFiles.filter (fun path => path.toString.endsWith ".lean")
      lines := lines ++ #[
        s!"### {markdown check.id.propertyId} v{check.id.definitionVersion} / {markdown check.id.modelId}", ""]
      if !generated.isEmpty then
        lines := lines ++ #["Generated Lean:", ""] ++ fileLines generated ++ #[""]
      else
        lines := lines ++ #["No generated Lean is retained for this attempt.", ""]
      if let some result := check.result then
        lines := lines ++ #[s!"Recorded verdict: **{result.status.label}**.", ""]
        for reason in result.reasons do
          lines := lines.push ("- " ++ markdown reason)
        if !result.reasons.isEmpty then lines := lines.push ""
      else if check.error.isNone && validator.preparationError.isNone then
        lines := lines ++ #[
          if run.finished then "No check result was recorded."
          else "Pending: no check result has been recorded at this checkpoint.", ""]
      if let some message := check.error then
        lines := lines ++ #["Check error: " ++ markdown message, ""]
      let records := checkFiles.filter fun path =>
        path.toString.endsWith ".json" || path.toString.endsWith ".log"
      if !records.isEmpty then
        lines := lines ++ #["Input, execution, results, and logs:", ""] ++ fileLines records ++ #[""]
  let sources := retained.filter fun path =>
    under "sources" path && !path.toString.endsWith ".olean" && !path.toString.endsWith ".tmp"
  lines := lines ++ #["## Shared source snapshots", ""]
  if sources.isEmpty then
    lines := lines ++ #["No shared source snapshots are retained at this checkpoint.", ""]
  else
    lines := lines ++ #[
      "These files are shared by the run. Consult the source index for capture details and any missing files.",
      ""] ++ fileLines sources ++ #[""]
  lines := lines ++ #[
    "Dependency sources and the runtime are not bundled. Independent replay is deferred.", ""]
  if !run.errors.isEmpty then
    lines := lines ++ #["## Run errors", ""] ++ run.errors.map (fun error => "- " ++ markdown error) ++ #[""]
  unless run.finished do
    lines := lines ++ #["This run has not finished. The page lists the files retained at this checkpoint.", ""]
  let temporary := run.directory / "README.md.tmp"
  writeText temporary (String.intercalate "\n" lines.toList)
  IO.FS.rename temporary (run.directory / "README.md")

end Workflow.App.Review

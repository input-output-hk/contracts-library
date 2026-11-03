namespace Workflow.Tests.Logging

/-- Print a progress message immediately, including when stdout is a pipe. -/
def line (message : String) : IO Unit := do
  let output ← IO.getStdout
  output.putStr (message ++ "\n")
  output.flush

private def drain (source : IO.FS.Handle) (destination : IO.FS.Stream)
    (log : Option IO.FS.Handle) : IO String := do
  let mut captured : Array String := #[]
  repeat
    let chunk ← source.getLine
    if chunk.isEmpty then break
    captured := captured.push chunk
    destination.putStr chunk
    destination.flush
    if let some file := log then
      file.putStr chunk
      file.flush
  return String.join captured.toList

/-- Stream both pipes concurrently while retaining their exact text and optional logs. -/
def run (args : IO.Process.SpawnArgs)
    (stdoutLog stderrLog : Option System.FilePath := none) : IO IO.Process.Output := do
  let stdoutFile ← match stdoutLog with
    | none => pure none
    | some path => some <$> IO.FS.Handle.mk path .write
  let stderrFile ← match stderrLog with
    | none => pure none
    | some path => some <$> IO.FS.Handle.mk path .write
  let stdout ← IO.getStdout
  let stderr ← IO.getStderr
  let child ← IO.Process.spawn { args with stdin := .null, stdout := .piped, stderr := .piped }
  let read := fun source destination log => do
    try drain source destination log
    catch error =>
      try child.kill catch _ => pure ()
      throw error
  try
    let stdoutTask ← IO.asTask (read child.stdout stdout stdoutFile) Task.Priority.dedicated
    let stderrTask ← IO.asTask (read child.stderr stderr stderrFile) Task.Priority.dedicated
    let out ← IO.ofExcept stdoutTask.get
    let err ← IO.ofExcept stderrTask.get
    let exitCode ← child.wait
    return { exitCode, stdout := out, stderr := err }
  catch error =>
    try child.kill catch _ => pure ()
    try let _ ← child.wait; pure () catch _ => pure ()
    throw error

end Workflow.Tests.Logging

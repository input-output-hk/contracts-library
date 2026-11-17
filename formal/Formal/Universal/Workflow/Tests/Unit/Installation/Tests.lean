import Init.System.IO

def main : IO UInt32 := do
  let process ← IO.Process.spawn {
    cmd := "bash", args := #["Formal/Universal/Workflow/Tests/Unit/Installation/launcher.sh"] }
  process.wait

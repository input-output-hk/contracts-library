import Init.System.IO

def main : IO UInt32 := do
  let process ← IO.Process.spawn {
    cmd := "bash", args := #["Workflow/Tests/Unit/Installation/launcher.sh"] }
  process.wait

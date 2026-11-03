import Init.System.IO

def main : IO UInt32 := do
  let process ← IO.Process.spawn {
    cmd := "python3"
    args := #["-I", "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_property_discovery.py"] }
  return ← process.wait

import Init.System.IO

def main : IO UInt32 := do
  let process ← IO.Process.spawn {
    cmd := "python3"
    args := #["-I", "-B", "tests/test_public_declarative_cli.py"] }
  return ← process.wait

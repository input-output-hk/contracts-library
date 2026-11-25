"""Exercise the milestone checker with small Lean fixtures. Run with Python 3."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

FORMAL = Path(__file__).resolve().parents[2]
CHECKER = FORMAL / "scripts/check-m1-2-proofs.lean"
GOOD = "theorem valid : True := True.intro"
FULL = "Formal.LinearVesting.Spec.valid"


class ProofCheck(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.modules = self.root / "Formal/LinearVesting"
        self.modules.mkdir(parents=True)
        (self.root / "lean-toolchain").write_bytes((FORMAL / "lean-toolchain").read_bytes())
        (self.root / "Formal.lean").write_text("import Formal.LinearVesting\n")
        (self.root / "Formal/LinearVesting.lean").write_text("import Formal.LinearVesting.Spec\n")

    def lean(self, *args):
        return subprocess.run(
            ["lean", *args], cwd=self.root, env={**os.environ, "LEAN_PATH": str(self.root)},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
        )

    def compile_fixture(self, body, imports=""):
        (self.modules / "Spec.lean").write_text(
            f"{imports}\nnamespace Formal.LinearVesting.Spec\n{body}\nend Formal.LinearVesting.Spec\n"
        )
        messages = []
        for name in ["Formal/LinearVesting/Spec", "Formal/LinearVesting", "Formal"]:
            result = self.lean("-o", name + ".olean", name + ".lean")
            self.assertEqual(result.returncode, 0, result.stdout)
            messages.append(result.stdout)
        return "".join(messages)

    def check(self, catalogue, error=None):
        (self.modules / "properties.json").write_text(json.dumps(catalogue))
        result = self.lean(str(CHECKER))
        if error is None:
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("proof audit passed", result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(error, result.stdout)

    def test_catalogue_and_warnings(self):
        log = self.compile_fixture("def idWithUnusedArgument (x : Nat) := 1\n" + GOOD)
        self.assertIn("warning:", log)
        self.check([{"id": "LV-001", "theorems": [FULL]}])
        self.check([], "catalogue is empty")
        for refs, error in [
            ([], "no theorem references"),
            ([FULL + "Missing"], "is missing or is not a theorem"),
            (["Formal.LinearVesting.Spec.idWithUnusedArgument"], "is missing or is not a theorem"),
        ]:
            with self.subTest(refs=refs):
                self.check([{"id": "LV-001", "theorems": refs}], error)

    def test_transitive_sorry_with_warning_disabled(self):
        (self.root / "Dependency.lean").write_text(
            "set_option warn.sorry false\ntheorem unfinishedHelper : True := by sorry\n"
        )
        result = self.lean("-o", "Dependency.olean", "Dependency.lean")
        self.assertEqual(result.returncode, 0, result.stdout)
        log = self.compile_fixture("theorem valid : True := unfinishedHelper", "import Dependency")
        self.assertNotIn("warning:", result.stdout + log)
        self.check([{"id": "LV-001", "theorems": [FULL]}], "disallowed axiom")

        self.compile_fixture(GOOD + "\ntheorem other : True := unfinishedHelper", "import Dependency")
        self.check([{"id": "LV-001", "theorems": [FULL]}], "Spec.other depends on disallowed axioms")

    def test_unlisted_milestone_sorry(self):
        self.compile_fixture(GOOD + "\nset_option warn.sorry false in\ntheorem unfinished : True := by sorry")
        self.check([{"id": "LV-001", "theorems": [FULL]}], "contains sorryAx")


    def test_unlisted_root_sorry(self):
        (self.root / "Formal.lean").write_text(
            "import Formal.LinearVesting\nset_option warn.sorry false\ntheorem unfinishedRoot : True := by sorry\n"
        )
        self.compile_fixture(GOOD)
        self.check([{"id": "LV-001", "theorems": [FULL]}], "unfinishedRoot contains sorryAx")

    def test_omitted_milestone(self):
        (self.root / "Formal.lean").write_text("import Lean\n")
        self.compile_fixture(GOOD)
        self.check([{"id": "LV-001", "theorems": [FULL]}], "must import the M1.2 milestone")


if __name__ == "__main__":
    unittest.main()

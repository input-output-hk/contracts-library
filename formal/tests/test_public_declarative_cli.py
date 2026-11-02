"""Public-command integration checks. Add --proofs for bounded real solver runs."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "plutus-upv"
PROOFS = "--proofs" in sys.argv
if PROOFS:
    sys.argv.remove("--proofs")


class PublicCLIIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = Path(tempfile.mkdtemp(prefix="public-cli.", dir=ROOT / "output"))
        cls.records = []
        print(f"Public CLI test evidence: {cls.evidence}", flush=True)

    def invoke(self, label, args, expected_code=0, cwd=ROOT):
        command = [str(CLI), *map(str, args)]
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=1800)
        prefix = self.evidence / label
        prefix.with_suffix(".stdout.log").write_text(result.stdout)
        prefix.with_suffix(".stderr.log").write_text(result.stderr)
        record = {"case": label, "command": command, "cwd": str(cwd), "exit_code": result.returncode}
        self.records.append(record)
        (self.evidence / "summary.json").write_text(json.dumps(self.records, indent=2) + "\n")
        self.assertEqual(result.returncode, expected_code, result.stdout + result.stderr)
        print(label, result.returncode, flush=True)
        return result

    def output(self, result):
        paths = [line.removeprefix("Output: ").strip() for line in result.stdout.splitlines()
                 if line.startswith("Output: ")]
        self.assertEqual(len(paths), 1, result.stdout)
        root = Path(paths[0])
        index = json.loads((root / "run.json").read_text())
        self.assertTrue(index["finished"], index)
        self.assertEqual(index["errors"], [])
        self.assertEqual(index["options"]["discovery_snapshot"], "discovery.json")
        self.assertTrue((root / "discovery.json").is_file())
        checks = {}
        for validator in index["validators"]:
            for check in validator["checks"]:
                self.assertIsNone(check["error"], check)
                checks[(validator["name"], check["property"]["id"], check["tx_model"])] = \
                    json.loads((root / check["result"]).read_text())
        self.records[-1].update({"run": str(root), "results": [
            {"validator": key[0], "property": key[1], "model": key[2], "status": value["status"]}
            for key, value in checks.items()]})
        (self.evidence / "summary.json").write_text(json.dumps(self.records, indent=2) + "\n")
        return root, index, checks

    def counts(self, result, validator, expected):
        line = next(line for line in result.stdout.splitlines() if line.split()[:1] == [validator])
        self.assertEqual(list(map(int, line.split()[1:])), expected, line)

    def test_a_help_and_invalid_usage(self):
        result = self.invoke("help", ["--help"])
        self.assertIn("Plutus UPV", result.stdout)
        self.invoke("invalid-usage", ["run", "--timeout-ms", "0"], expected_code=2)

    def test_b_no_enabled_checks(self):
        switches = self.evidence / "all disabled.json"
        switches.write_text('{"UP-001": false, "UP-012": false, "UP-015": false}')
        result = self.invoke("empty-selection", ["run", ROOT / "Workflow/Tests/UP012/Inputs/unsupported.json",
                                                  "--checks-file", switches])
        root, _, checks = self.output(result)
        self.assertEqual(checks, {})
        self.assertEqual((root / "checks.json").read_text(), switches.read_text())
        self.assertIn("No checks selected", result.stdout)

    def test_c_caller_paths_and_disabled_known_properties(self):
        caller = self.evidence / "caller with spaces"
        caller.mkdir()
        blueprint = ROOT / "Workflow/Tests/UP012/Inputs/unsupported.json"
        (caller / "plutus.json").write_bytes(blueprint.read_bytes())
        source = '{\r\n"UP-001": false, "UP-012": false, "UP-015": true\r\n}\r\n'
        (caller / "my checks.json").write_bytes(source.encode("utf-8"))
        result = self.invoke("caller-paths", ["run", "--checks-file", "my checks.json"], cwd=caller)
        root, index, checks = self.output(result)
        self.assertEqual(len(checks), 1)
        self.assertEqual((root / "checks.json").read_bytes().decode("utf-8"), source)
        self.assertEqual(index["options"]["blueprint"], str(caller / "plutus.json"))
        self.assertEqual(index["options"]["selection_file"], str(caller / "my checks.json"))
        self.counts(result, "unsupported.validator", [0, 0, 1, 0, 0])

    def test_d_unused_broken_sources_do_not_block_selected_checks(self):
        existing = ROOT / "Formal/TxModels/Definitions/TxM009.lean"
        saved = existing.read_bytes()
        extra_model = ROOT / "Formal/TxModels/Definitions/TxM999.lean"
        extra_property = ROOT / "Formal/Properties/Universal/UP999"
        self.assertFalse(extra_model.exists())
        self.assertFalse(extra_property.exists())
        created = []
        try:
            existing.write_bytes(saved + b"\nthis deliberately does not compile\n")
            extra_model.write_bytes(b"\xff\xfe deliberately invalid unused source")
            extra_property.mkdir()
            for name, text in {
                "Definition.lean": "def unused : Prop := True\n",
                "Run.lean": "this deliberately does not compile\n",
                "metadata.json": json.dumps({"identity": {"id": "UP-999", "definition_version": 1}}),
            }.items():
                path = extra_property / name
                path.write_text(text)
                created.append(path)
            switches = self.evidence / "isolated checks.json"
            switches.write_text('{"UP-001": false, "UP-012": false, "UP-015": true, "UP-999": false}')
            result = self.invoke("unused-source-isolation", [
                "run", ROOT / "Workflow/Tests/UP012/Inputs/unsupported.json", "--checks-file", switches])
            root, _, checks = self.output(result)
            self.assertEqual(len(checks), 1)
            preparation = json.loads((root / "discovery.json").read_text())
            self.assertEqual(preparation["selected_models"]["models"], ["TxM-007"])
            self.assertEqual(preparation["selected_properties"], ["UP-015"])
            self.counts(result, "unsupported.validator", [0, 0, 1, 0, 0])
            failed = self.invoke("selected-source-error", [
                "run", ROOT / "Workflow/Tests/UP012/Inputs/unsupported.json", "--check", "UP-999"], expected_code=2)
            self.assertIn("Could not prepare selected checks", failed.stderr)
            self.assertNotIn("Recorded checks:", failed.stdout)
            paths = [line.removeprefix("Preparation evidence: ").strip()
                     for line in failed.stderr.splitlines() if line.startswith("Preparation evidence: ")]
            self.assertEqual(len(paths), 1)
            self.assertEqual(json.loads(Path(paths[0]).read_text())["state"], "failed")
        finally:
            existing.write_bytes(saved)
            if extra_model.exists():
                extra_model.unlink()
            for path in created:
                path.unlink()
            if extra_property.exists():
                extra_property.rmdir()
        self.assertEqual(existing.read_bytes(), saved)

    def test_e_runtime_timeout_keeps_evidence(self):
        result = self.invoke("runtime-timeout", [
            "run", ROOT / "Workflow/Tests/UP012/Inputs/plutus.json", "--check", "UP-015", "--timeout-ms", "1"])
        root, _, checks = self.output(result)
        self.assertEqual(len(checks), 1)
        self.assertEqual(next(iter(checks.values()))["status"], "INCONCLUSIVE")
        self.counts(result, "linear_vesting.linear_vesting", [0, 0, 0, 0, 1])
        executions = list(root.glob("validators/*/*/execution.json"))
        self.assertEqual(len(executions), 1)
        self.assertIn("timed", json.loads(executions[0].read_text())["state"].lower())

    @unittest.skipUnless(PROOFS, "add --proofs to run bounded real validators")
    def test_f_real_vesting_properties(self):
        result = self.invoke("vesting-properties", [
            "run", ROOT / "Workflow/Tests/UP012/Inputs/plutus.json",
            "--check", "UP-012", "--check", "UP-015", "--timeout-ms", "300000"])
        root, _, checks = self.output(result)
        expected = {("UP-012", "TxM-007"): "PASS", ("UP-012", "TxM-008"): "PASS",
                    ("UP-012", "TxM-009"): "INCONCLUSIVE", ("UP-015", "TxM-007"): "PASS"}
        self.assertEqual({(p, m): value["status"] for (_, p, m), value in checks.items()}, expected)
        self.counts(result, "linear_vesting.linear_vesting", [3, 0, 1, 0, 0])
        sources = json.loads((root / "sources/index.json").read_text())
        modules = [entry["module"] for entry in sources["sources"]]
        self.assertIn("Formal.Properties.Universal.UP012.Run", modules)
        self.assertIn("Formal.Properties.Universal.UP015.Run", modules)

    @unittest.skipUnless(PROOFS, "add --proofs to run bounded real validators")
    def test_g_real_vault_controls(self):
        result = self.invoke("vault-controls", [
            "run", ROOT / "Workflow/Tests/UP001/Inputs/plutus.json", "--check", "UP-012", "--timeout-ms", "300000"])
        _, _, checks = self.output(result)
        self.assertEqual(checks[("vault.vault", "UP-012", "TxM-009")]["status"], "PASS")
        self.assertEqual(checks[("vault_buggy.vault_buggy", "UP-012", "TxM-009")]["status"], "FAIL")
        self.counts(result, "vault.vault", [1, 0, 2, 0, 0])
        self.counts(result, "vault_buggy.vault_buggy", [0, 1, 2, 0, 0])

    @unittest.skipUnless(PROOFS, "add --proofs to run bounded real validators")
    def test_h_false_applicability_is_not_a_pass(self):
        result = self.invoke("false-applicability", [
            "run", ROOT / "Workflow/Tests/UP012/Inputs/reusable.json", "never_accept",
            "--check", "UP-012", "--timeout-ms", "300000"])
        _, _, checks = self.output(result)
        check = checks[("never_accept.never_accept", "UP-012", "TxM-009")]
        self.assertEqual(check["status"], "INCONCLUSIVE")
        self.assertEqual({o["name"]: o["observed"] for o in check["obligations"]},
                         {"dropSigner_spend": "valid", "dropSigner_spend_applies": "falsified"})
        self.counts(result, "never_accept.never_accept", [0, 0, 2, 1, 0])

    @unittest.skipUnless(PROOFS, "add --proofs to run bounded real validators")
    def test_i_legacy_up001_and_declarative_selection_together(self):
        result = self.invoke("legacy-up001", [
            "run", ROOT / "Workflow/Tests/UP001/Inputs/plutus.json", "--check", "UP-001",
            "--check", "UP-015", "--timeout-ms", "300000"])
        _, _, checks = self.output(result)
        self.assertEqual(len(checks), 14)
        self.counts(result, "vault.vault", [5, 0, 2, 0, 0])
        self.counts(result, "vault_buggy.vault_buggy", [0, 5, 2, 0, 0])

    def test_j_default_selection_preserves_all_available_checks(self):
        data = json.loads((ROOT / "Workflow/Tests/UP001/Inputs/plutus.json").read_text())
        data["validators"] = [entry for entry in data["validators"]
                              if entry["title"].startswith("vault.vault.")]
        # Parameter application remains unsupported by every existing binding.
        for entry in data["validators"]:
            entry["parameters"] = [{"title": "testParameter", "schema": {"dataType": "bytes"}}]
        path = self.evidence / "unapplied parameter.json"
        path.write_text(json.dumps(data))
        result = self.invoke("default-selection", ["run", path])
        _, _, checks = self.output(result)
        self.assertEqual(len(checks), 10)
        self.assertTrue(all(value["status"] == "INCONCLUSIVE" and not value["obligations"]
                            for value in checks.values()))
        self.counts(result, "vault.vault", [0, 0, 10, 0, 0])


if __name__ == "__main__":
    unittest.main()

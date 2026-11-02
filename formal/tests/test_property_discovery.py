import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/run_properties.py"
SPEC = importlib.util.spec_from_file_location("run_properties", SCRIPT)
discovery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(discovery)


class PropertyDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.property = self.root / "Formal/Properties/Universal/UP777"
        self.property.mkdir(parents=True)
        (self.property / "Run.lean").write_text("def run := ()\n")
        (self.property / "Definition.lean").write_text("def statement := True\n")
        (self.property / "metadata.json").write_text(json.dumps({"identity": {"id": "UP-777"}}))
        self.models = self.root / "Formal/TxModels/Definitions"
        self.models.mkdir(parents=True)
        (self.models / "TxM777.lean").write_text("def runnable : Runnable := {}\n")

    def properties(self):
        entries, errors = discovery.candidates(self.root)
        self.assertEqual(errors, [])
        return discovery.properties_for(self.root, entries, ["UP-777"])

    def test_new_property_and_model_need_no_central_registration(self):
        properties = self.properties()
        models = discovery.models_for(self.root, ["TxM-777"])
        text = discovery.bootstrap(properties, models)
        self.assertIn("import Formal.Properties.Universal.UP777.Run", text)
        self.assertIn("import Formal.TxModels.Definitions.TxM777", text)
        self.assertIn("Formal.Properties.Universal.UP777.run", text)
        self.assertIn("Formal.TxModels.TxM777.runnable", text)
        self.assertFalse((self.root / "Candidates").exists())

    def test_planning_does_not_import_models(self):
        text = discovery.plan_source(self.properties(), False)
        self.assertNotIn("import Formal.TxModels.Definitions", text)
        self.assertIn("Discovery.describe", text)

    def test_an_unused_broken_model_is_not_read_or_imported(self):
        (self.models / "TxM999.lean").write_bytes(b"\xff\xfe invalid Lean")
        models = discovery.models_for(self.root, ["TxM-777"])
        text = discovery.bootstrap(self.properties(), models)
        self.assertNotIn("TxM999", text)

    def test_selected_model_requires_an_execution_export(self):
        (self.models / "TxM777.lean").write_text("def context := ()\n")
        with self.assertRaisesRegex(ValueError, "runnable"):
            discovery.models_for(self.root, ["TxM-777"])

    def test_indented_and_qualified_model_exports_are_discovered(self):
        (self.models / "TxM777.lean").write_text(
            "namespace Formal.TxModels.TxM777\n  def runnable : Formal.TxModels.Runnable := {}\n")
        self.assertEqual(len(discovery.models_for(self.root, ["TxM-777"])), 1)

    def test_invalid_model_ids_and_missing_models_are_rejected(self):
        for identity in ["../TxM-777", "TxM-999"]:
            with self.assertRaises(ValueError):
                discovery.models_for(self.root, [identity])

    def test_unselected_incomplete_property_does_not_block_selection(self):
        folder = self.property.with_name("UP999")
        folder.mkdir()
        (folder / "Run.lean").write_text("invalid Lean")
        (folder / "metadata.json").write_text(json.dumps({"identity": {"id": "UP-999"}}))
        entries, _ = discovery.candidates(self.root)
        properties = discovery.properties_for(self.root, entries, ["UP-777"])
        self.assertEqual(len(properties), 1)
        with self.assertRaisesRegex(ValueError, "Definition.lean"):
            discovery.properties_for(self.root, entries, ["UP-999"])

    def test_malformed_unselected_metadata_is_reported_without_loading_its_run(self):
        folder = self.property.with_name("UP999")
        folder.mkdir()
        (folder / "Run.lean").write_text("invalid Lean")
        (folder / "metadata.json").write_text("broken JSON")
        entries, errors = discovery.candidates(self.root)
        self.assertEqual(len(errors), 1)
        self.assertEqual(len(discovery.properties_for(self.root, entries, ["UP-777"])), 1)

    def test_disabled_known_properties_do_not_need_compiled_checks(self):
        path = self.root / "my checks.json"
        source = '{\r\n"UP-777": true, "UP-999": false\r\n}\r\n'
        path.write_bytes(source.encode("utf-8"))
        selected, captured = discovery.selection(["--checks-file", str(path)], ["UP-777", "UP-999"])
        self.assertEqual(selected, ["UP-777"])
        self.assertEqual(captured, source)
        path.write_text("changed later")
        self.assertEqual(captured, source)

    def test_selection_is_strict_and_preserves_registry_order(self):
        selected, _ = discovery.selection(["--check", "UP-999", "--check", "UP-777"], ["UP-777", "UP-999"])
        self.assertEqual(selected, ["UP-777", "UP-999"])
        path = self.root / "checks.json"
        for data in [{"UP-777": 1}, {"unknown": False}, []]:
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                discovery.selection(["--checks-file", str(path)], ["UP-777"])

    def test_empty_selection_remains_empty(self):
        path = self.root / "checks.json"
        path.write_text('{"UP-777": false}')
        self.assertEqual(discovery.selection(["--checks-file", str(path)], ["UP-777"])[0], [])

    def test_invalid_module_paths_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "module path"):
            discovery.module_name(self.root, self.root / "Formal/Bad-Name.lean")

    def test_generated_paths_preserve_non_ascii_text(self):
        text = discovery.bootstrap(self.properties(), [], snapshot=Path("/tmp/é checks.json"))
        self.assertIn("é checks.json", text)
        self.assertNotIn("\\u00e9", text)

    def test_real_properties_have_no_direct_model_imports(self):
        root = SCRIPT.parents[1]
        for code in ["UP012", "UP015"]:
            source = (root / f"Formal/Properties/Universal/{code}/Run.lean").read_text()
            self.assertNotIn("import Formal.TxModels.Definitions.", source)

    def test_preparation_deadline_kills_the_build_process_group_and_retains_logs(self):
        tools = self.root / "tools"
        tools.mkdir()
        lake = tools / "lake"
        lake.write_text(
            f"#!{sys.executable}\nimport subprocess\nfrom pathlib import Path\n"
            "process = subprocess.Popen(['/bin/sleep', '60'])\n"
            "Path('child.pid').write_text(str(process.pid))\nprocess.wait()\n")
        lake.chmod(0o755)
        with patch.object(discovery, "__file__", str(self.root / "scripts/run_properties.py")), \
                patch.object(discovery, "preparation_budget", return_value=0.2), \
                patch.dict(os.environ, {"PATH": str(tools) + os.pathsep + os.environ["PATH"]}), \
                contextlib.redirect_stderr(io.StringIO()):
            result = discovery.main(["--check", "UP-777"])
        self.assertEqual(result, 2)
        indices = list((self.root / "output").glob("discovery.*/index.json"))
        record = json.loads(indices[0].read_text())
        self.assertEqual(record["state"], "failed")
        self.assertEqual(record["commands"][0]["state"], "timedOut")
        self.assertTrue(Path(record["commands"][0]["stdout"]).is_file())
        child = int((self.root / "child.pid").read_text())
        status = Path(f"/proc/{child}/stat")
        if status.exists():
            self.assertEqual(status.read_text().split()[2], "Z")


if __name__ == "__main__":
    unittest.main()

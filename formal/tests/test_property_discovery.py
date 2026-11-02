import importlib.util
from pathlib import Path
import tempfile
import unittest


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
        (self.property / "metadata.json").write_text("{}\n")
        self.models = self.root / "Formal/TxModels/Definitions"
        self.models.mkdir(parents=True)

    def test_new_property_and_model_need_no_central_registration(self):
        (self.models / "TxM777.lean").write_text("def runnable : Runnable := {}\n")
        properties, models = discovery.discover(self.root)
        text = discovery.bootstrap(properties, models)
        self.assertIn("import Formal.Properties.Universal.UP777.Run", text)
        self.assertIn("import Formal.TxModels.Definitions.TxM777", text)
        self.assertIn("Formal.Properties.Universal.UP777.run", text)
        self.assertIn("Formal.TxModels.TxM777.runnable", text)
        self.assertFalse((self.root / "Candidates").exists())

    def test_models_without_execution_exports_are_not_invented(self):
        (self.models / "TxM777.lean").write_text("def context := ()\n")
        _, models = discovery.discover(self.root)
        self.assertEqual(models, [])

    def test_indented_and_qualified_model_exports_are_discovered(self):
        (self.models / "TxM777.lean").write_text(
            "namespace Formal.TxModels.TxM777\n  def runnable : Formal.TxModels.Runnable := {}\n")
        _, models = discovery.discover(self.root)
        self.assertEqual(len(models), 1)

    def test_missing_metadata_stops_discovery(self):
        (self.property / "metadata.json").unlink()
        with self.assertRaisesRegex(ValueError, "metadata.json"):
            discovery.discover(self.root)

    def test_invalid_module_paths_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "module path"):
            discovery.module_name(self.root, self.root / "Formal/Bad-Name.lean")

    def test_real_property_has_no_direct_model_imports(self):
        root = SCRIPT.parents[1]
        source = (root / "Formal/Properties/Universal/UP012/Run.lean").read_text()
        self.assertNotIn("import Formal.TxModels.Definitions.", source)


if __name__ == "__main__":
    unittest.main()

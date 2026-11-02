"""Stdlib-only regression tests for blueprint extraction and UP-001/UP-005 generation."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "process_blueprint.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "blueprint-foundation.json"
SPEC = importlib.util.spec_from_file_location("blueprint_foundation", SCRIPT)
BLUEPRINT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BLUEPRINT
SPEC.loader.exec_module(BLUEPRINT)


class BlueprintFoundationTests(unittest.TestCase):
    def setUp(self):
        self.blueprint = json.loads(FIXTURE.read_text())

    def generated(self, blueprint=None):
        lines, info = BLUEPRINT.generate(
            self.blueprint if blueprint is None else blueprint,
            "example", "Formal.Fixture.Blueprint", "Scripts"
        )
        return "\n".join(lines + [f"end {info.prefix}"]) + "\n"

    def cli(self, root, *args, blueprint=None):
        path = Path(root) / "plutus.json"
        path.write_text(json.dumps(self.blueprint if blueprint is None else blueprint))
        return subprocess.run(
            [sys.executable, "-I", "-B", str(SCRIPT), str(path), "example", *args],
            cwd=root, capture_output=True, text=True, timeout=30
        )

    def test_named_types_and_isdata(self):
        source = self.generated()
        self.assertIn("structure Fixture.Types.Datum where", source)
        self.assertIn("inductive Fixture.Types.Redeemer where", source)
        self.assertIn("instance : IsData Fixture.Types.Datum", source)
        self.assertIn("List (Int)", source)
        self.assertIn("List (ByteString × Int)", source)

    def test_program_and_execution_predicates(self):
        source = self.generated()
        self.assertIn("PlutusV3 single_cbor_hex", source)
        self.assertIn('"Scripts/fixture.example.cbor"', source)
        self.assertIn("Formal.Universal.Properties.rejectedWithin", source)
        self.assertNotIn("theorem ", source)
        self.assertNotIn("sorry", source)

    def test_parameters_preserve_order(self):
        self.blueprint["validators"][0]["parameters"] = [
            {"title": "owner", "schema": {"dataType": "bytes"}},
            {"title": "limit", "schema": {"dataType": "integer"}}
        ]
        source = self.generated()
        self.assertIn("structure Params where", source)
        self.assertLess(source.index("  owner : ByteString", source.index("structure Params")),
                        source.index("  limit : Int", source.index("structure Params")))
        self.assertIn("def args (p : Params)", source)
        self.assertIn("def accepts (fuel : Nat) (p : Params)", source)

    def test_option_and_bool(self):
        tr = BLUEPRINT.Translator({
            "Option<Int>": {"anyOf": [
                {"dataType": "constructor", "index": 0, "fields": [{"dataType": "integer"}]},
                {"dataType": "constructor", "index": 1, "fields": []}
            ]},
            "Bool": {"anyOf": [
                {"dataType": "constructor", "index": 0, "fields": []},
                {"dataType": "constructor", "index": 1, "fields": []}
            ]}
        })
        self.assertEqual(BLUEPRINT.lean_type(tr.ty({"$ref": "#/definitions/Option<Int>"}, "test")),
                         "Option (Int)")
        self.assertEqual(BLUEPRINT.lean_type(tr.ty({"$ref": "#/definitions/Bool"}, "test")),
                         "Bool")

    def test_tuple_type(self):
        tr = BLUEPRINT.Translator({})
        ty = tr.ty({"dataType": "list", "items": [
            {"dataType": "integer"}, {"dataType": "bytes"}
        ]}, "test")
        self.assertIn("Int", BLUEPRINT.lean_type(ty))
        self.assertIn("ByteString", BLUEPRINT.lean_type(ty))
        self.assertIn("×", BLUEPRINT.lean_type(ty))

    def test_reserved_field_is_quoted(self):
        self.blueprint["definitions"]["fixture/types/Datum"]["anyOf"][0]["fields"][0]["title"] = "where"
        self.assertIn("«where» : Int", self.generated())

    def test_unknown_schema_fails(self):
        self.blueprint["definitions"]["fixture/types/Datum"]["anyOf"][0]["fields"][0] = {
            "dataType": "unknown"
        }
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "unknown dataType"):
            self.generated()

    def test_missing_definition_fails(self):
        self.blueprint["validators"][0]["datum"]["schema"] = {"$ref": "#/definitions/missing"}
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "missing definition"):
            self.generated()

    def test_unsupported_version_fails(self):
        self.blueprint["preamble"]["plutusVersion"] = "v2"
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "not supported"):
            self.generated()

    def test_missing_validator_fails(self):
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "no validator"):
            BLUEPRINT.find_entries(self.blueprint, "missing")

    def test_ambiguous_validator_fails(self):
        other = copy.deepcopy(self.blueprint["validators"][0])
        other["title"] = "other.example.spend"
        self.blueprint["validators"].append(other)
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "ambiguous"):
            BLUEPRINT.find_entries(self.blueprint, "example")
        self.assertEqual(len(BLUEPRINT.find_entries(self.blueprint, "fixture.example")), 2)

    def test_mismatched_handler_code_fails(self):
        self.blueprint["validators"][1]["compiledCode"] = "420001"
        with self.assertRaisesRegex(BLUEPRINT.ExtractError, "different compiled code"):
            self.generated()

    def test_module_path_validation(self):
        self.assertEqual(BLUEPRINT.module_prefix("Formal/Fixture/Blueprint"),
                         "Formal.Fixture.Blueprint")
        for invalid in ("Other/Fixture", "Formal/lowercase", "../Formal/Fixture"):
            with self.subTest(invalid=invalid), self.assertRaises(BLUEPRINT.ExtractError):
                BLUEPRINT.module_prefix(invalid)

    def test_cli_cbor_is_exact_copy(self):
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root, "--cbor-only")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((Path(root) / "Scripts/fixture.example.cbor").read_text(), "4100")
            self.assertEqual(result.stdout.strip(), "Scripts/fixture.example.cbor")

    def test_cli_writes_only_types_and_keeps_other_files(self):
        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / "Formal/Fixture/Blueprint"
            out.mkdir(parents=True)
            protected = ("Tx.lean", "Checks.lean", "General.lean", "Honest.lean")
            for name in protected:
                (out / name).write_text("-- existing content\n")
            result = self.cli(root, "--out", "Formal/Fixture/Blueprint")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((out / "Types.lean").read_text(), self.generated())
            for name in protected:
                self.assertEqual((out / name).read_text(), "-- existing content\n")
            self.assertFalse((Path(root) / "Scripts").exists())

    def test_cli_unknown_schema_returns_failure(self):
        self.blueprint["validators"][0]["datum"]["schema"] = {"dataType": "unknown"}
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown dataType", result.stderr)

    def test_translation_table_needs_no_blueprint(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(SCRIPT), "--translation"],
            capture_output=True, text=True, timeout=30
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Schema form", result.stdout)

    def other_purpose_source(self):
        _, info = BLUEPRINT.generate(self.blueprint, "example", "Formal.Fixture.Blueprint", "Scripts")
        return "\n".join(BLUEPRINT.other_purpose_checks(info)) + "\n"

    def test_other_purpose_preserves_unrestricted_original_claims(self):
        for declared in BLUEPRINT.PURPOSES:
            with self.subTest(declared=declared):
                self.blueprint["validators"][0]["title"] = f"fixture.example.{declared}"
                source = self.other_purpose_source()
                self.assertEqual(source.count("theorem otherPurpose_"), 5)
                self.assertNotIn(f"theorem otherPurpose_{declared}", source)
                for purpose, ctx in BLUEPRINT.EVERY.items():
                    if purpose != declared:
                        self.assertIn(f"theorem otherPurpose_{purpose} :\n"
                                      f"    ∀ (r : Data) (t : {ctx}),\n"
                                      f"      ¬ accepts ledgerFuel ({ctx}.ctx t r) := by blaster", source)
                for absent in (".Tx", "someAccepted", "validScriptContext", "rejects ledgerFuel", "sorry"):
                    self.assertNotIn(absent, source)

    def test_other_purpose_keeps_parameters_open(self):
        self.blueprint["validators"][0]["parameters"] = [
            {"title": "owner", "schema": {"dataType": "bytes"}}
        ]
        source = self.other_purpose_source()
        self.assertEqual(source.count("(p : Params)"), 5)
        self.assertIn("¬ accepts ledgerFuel p (EveryMint.ctx t r)", source)
        self.assertNotIn("honestParams", source)

    def test_other_purpose_skips_multiple_declared_handlers(self):
        mint = copy.deepcopy(self.blueprint["validators"][0])
        mint["title"] = "fixture.example.mint"
        self.blueprint["validators"].append(mint)
        source = self.other_purpose_source()
        self.assertEqual(source.count("theorem otherPurpose_"), 4)
        self.assertNotIn("theorem otherPurpose_spend", source)
        self.assertNotIn("theorem otherPurpose_mint", source)

    def test_other_purpose_reports_when_no_goals_apply(self):
        entry = self.blueprint["validators"][0]
        self.blueprint["validators"] = [dict(entry, title=f"fixture.example.{p}")
                                        for p in BLUEPRINT.PURPOSES]
        self.assertNotIn("theorem ", self.other_purpose_source())
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root, "--check", "otherPurpose")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("no undeclared purposes; no checks apply", result.stdout)
            checks = (Path(root) / "Formal/Blueprint/Checks.lean").read_text()
            self.assertIn("no UP-001 goals apply", checks)

    def test_cli_other_purpose_needs_no_transaction_file(self):
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root, "--out", "Formal/Fixture/Blueprint", "--check", "otherPurpose")
            self.assertEqual(result.returncode, 0, result.stderr)
            out = Path(root) / "Formal/Fixture/Blueprint"
            self.assertEqual({p.name for p in out.iterdir()}, {"Types.lean", "Checks.lean"})
            self.assertEqual((out / "Checks.lean").read_text(), self.other_purpose_source())
            self.assertEqual((out / "Types.lean").read_text(), self.generated())

    def test_cli_other_purpose_preserves_author_files(self):
        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / "Formal/Fixture/Blueprint"
            out.mkdir(parents=True)
            for name in ("Tx.lean", "General.lean", "Honest.lean"):
                (out / name).write_text("-- author content\n")
            (out / "Checks.lean").write_text("-- previous generated checks\n")
            result = self.cli(root, "--out", "Formal/Fixture/Blueprint", "--check", "otherPurpose")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((out / "Checks.lean").read_text(), self.other_purpose_source())
            for name in ("Tx.lean", "General.lean", "Honest.lean"):
                self.assertEqual((out / name).read_text(), "-- author content\n")

    def check_source(self):
        _, info = BLUEPRINT.generate(self.blueprint, "example", "Formal.Fixture.Blueprint", "Scripts")
        return "\n".join(BLUEPRINT.malformed_redeemer_checks(info)) + "\n"

    def test_malformed_constructor_cases_preserve_original_claim(self):
        source = self.check_source()
        names = set(re.findall(r"theorem malformedRedeemer_spend_(\w+)", source))
        self.assertEqual(names, {
            "wrongForm_int", "wrongForm_bytes", "wrongForm_list", "wrongForm_map",
            "unknownIndex2", "unknownIndex3", "Use_extraField", "Cancel_extraField",
            "Cancel_missingField", "Cancel_wrongKind_reason"
        })
        self.assertEqual(source.count("¬ accepts ledgerFuel"), len(names))
        self.assertIn("∀ (fs : List Data) (t : EverySpend),", source)
        for absent in (".Tx", "someAccepted", "validScriptContext", "rejects ledgerFuel", "sorry"):
            self.assertNotIn(absent, source)

    def test_unknown_tags_exclude_declared_tags(self):
        constructors = self.blueprint["definitions"]["fixture/types/Redeemer"]["anyOf"]
        constructors[1]["index"] = 2
        source = self.check_source()
        self.assertIn("malformedRedeemer_spend_unknownIndex1", source)
        self.assertIn("malformedRedeemer_spend_unknownIndex3", source)
        self.assertNotIn("malformedRedeemer_spend_unknownIndex2", source)
        for tags in ((0,), (0, 1), (0, 2), (1, 3), (8, 13)):
            with self.subTest(tags=tags):
                ctors = [(f"R.C{i}", i, []) for i in tags]
                cases = BLUEPRINT.malformed(BLUEPRINT.Translator({}), "constructors", ctors, 0)
                indices = [int(name.removeprefix("unknownIndex"))
                           for name, _, _, _ in cases if name.startswith("unknownIndex")]
                self.assertEqual(len(set(indices)), 2)
                self.assertFalse(set(indices).intersection(tags))
                if list(tags) == list(range(len(tags))):
                    self.assertEqual(indices, [len(tags), len(tags) + 1])

    def test_malformed_checks_keep_parameters_and_contexts_open(self):
        self.blueprint["validators"][0]["parameters"] = [
            {"title": "owner", "schema": {"dataType": "bytes"}}
        ]
        for purpose, context in BLUEPRINT.EVERY.items():
            with self.subTest(purpose=purpose):
                self.blueprint["validators"][0]["title"] = f"fixture.example.{purpose}"
                source = self.check_source()
                self.assertIn(f"malformedRedeemer_{purpose}_wrongForm_int (p : Params)", source)
                self.assertIn(f"∀ (n : Int) (t : {context}),", source)
                self.assertIn(f"¬ accepts ledgerFuel p ({context}.ctx t (Data.I n))", source)
                self.assertNotIn("honestParams", source)

    def test_primitive_redeemer_uses_its_selected_wrong_forms(self):
        for kind in ("integer", "bytes", "list", "map"):
            with self.subTest(kind=kind):
                self.blueprint["validators"][0]["redeemer"]["schema"] = {"dataType": kind}
                source = self.check_source()
                right_form = "int" if kind == "integer" else kind
                self.assertNotIn(f"theorem malformedRedeemer_spend_wrongForm_{right_form}", source)
                for form in {"int", "bytes", "list", "map"} - {right_form}:
                    self.assertIn(f"theorem malformedRedeemer_spend_wrongForm_{form}", source)

    def test_untyped_redeemer_reports_no_goals(self):
        self.blueprint["validators"][0]["redeemer"]["schema"] = {}
        self.assertNotIn("theorem ", self.check_source())
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root, "--check", "malformedRedeemer")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("no typed redeemer cases; no checks generated", result.stdout)

    def test_field_cases_preserve_fixed_sibling_list_scope(self):
        fields = self.blueprint["definitions"]["fixture/types/Redeemer"]["anyOf"][1]["fields"]
        fields[0] = {"title": "items", "dataType": "list", "items": {"dataType": "integer"}}
        fields.append({"title": "amount", "dataType": "integer"})
        source = self.check_source()
        self.assertIn("malformedRedeemer_spend_Cancel_wrongKind_amount", source)
        self.assertIn("Data.Constr 1 [(Data.List []), (Data.B x1)]", source)

    def test_cli_malformed_redeemer_needs_no_transaction_file(self):
        with tempfile.TemporaryDirectory() as root:
            result = self.cli(root, "--out", "Formal/Fixture/Blueprint", "--check", "malformedRedeemer")
            self.assertEqual(result.returncode, 0, result.stderr)
            out = Path(root) / "Formal/Fixture/Blueprint"
            self.assertEqual({p.name for p in out.iterdir()}, {"Types.lean", "Checks.lean"})
            self.assertEqual((out / "Types.lean").read_text(), self.generated())
            self.assertEqual((out / "Checks.lean").read_text(), self.check_source())

    def test_cli_malformed_redeemer_preserves_author_files(self):
        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / "Formal/Fixture/Blueprint"
            out.mkdir(parents=True)
            for name in ("Tx.lean", "General.lean", "Honest.lean"):
                (out / name).write_text("-- author content\n")
            (out / "Checks.lean").write_text("-- previous generated checks\n")
            result = self.cli(root, "--out", "Formal/Fixture/Blueprint", "--check", "malformedRedeemer")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((out / "Checks.lean").read_text(), self.check_source())
            for name in ("Tx.lean", "General.lean", "Honest.lean"):
                self.assertEqual((out / name).read_text(), "-- author content\n")

    def test_cli_rejects_unsupported_or_conflicting_check_options(self):
        for args in (("--check", "someAccepted"), ("--check", "unknown"),
                     ("--cbor-only", "--check", "otherPurpose"),
                     ("--cbor-only", "--check", "malformedRedeemer")):
            with self.subTest(args=args), tempfile.TemporaryDirectory() as root:
                result = self.cli(root, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((Path(root) / "Formal").exists())
                self.assertFalse((Path(root) / "Scripts").exists())


if __name__ == "__main__":
    unittest.main()

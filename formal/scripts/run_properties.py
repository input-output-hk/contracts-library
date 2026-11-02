#!/usr/bin/env python3
"""Experimental discovery of property Run.lean files and native model exports.

Usage from formal/: python3 scripts/run_properties.py BLUEPRINT [normal run options]
                  python3 scripts/run_properties.py --list
"""

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def module_name(root, path):
    parts = path.relative_to(root).with_suffix("").parts
    if not all(re.fullmatch(r"[A-Z][A-Za-z0-9_]*", part) for part in parts):
        raise ValueError(f"invalid Lean module path: {path}")
    return ".".join(parts)


def discover(root):
    properties = []
    for path in sorted((root / "Formal/Properties").rglob("Run.lean")):
        definition = path.with_name("Definition.lean")
        metadata = path.with_name("metadata.json")
        if not definition.is_file() or not metadata.is_file():
            raise ValueError(f"{path}: requires Definition.lean and metadata.json")
        module = module_name(root, path)
        properties.append((module, module.removesuffix(".Run") + ".run",
                           module_name(root, definition), str(metadata.relative_to(root))))
    models = []
    for path in sorted((root / "Formal/TxModels/Definitions").glob("TxM*.lean")):
        # This experiment uses one conventional export; Lean checks its actual type.
        if re.search(r"^[ \t]*def runnable\s*:\s*(?:Formal\.TxModels\.)?Runnable\s*:=",
                     path.read_text(), re.MULTILINE):
            module = module_name(root, path)
            models.append((module, f"Formal.TxModels.{path.stem}.runnable"))
    if not properties:
        raise ValueError("no property Run.lean files discovered")
    return properties, models


def bootstrap(properties, models):
    imports = list(dict.fromkeys(["Workflow.Declarative.CLI"] +
                               [p[0] for p in properties] + [m[0] for m in models]))
    property_entries = [
        "{ run := " + name + ", runModule := " + json.dumps(module) +
        ", definitionModule := " + json.dumps(definition) +
        ", metadataPath := " + json.dumps(metadata) + " }"
        for module, name, definition, metadata in properties
    ]
    model_entries = [
        "{ moduleName := " + json.dumps(module) + ", runnable := " + name + " }"
        for module, name in models
    ]
    return "\n".join("import " + name for name in imports) + "\n\n" + \
        "def main (args : List String) : IO UInt32 :=\n" + \
        "  Workflow.Declarative.main\n    #[" + ",\n      ".join(property_entries) + \
        "]\n    #[" + ",\n      ".join(model_entries) + "] args\n"


def main(args):
    root = Path(__file__).resolve().parents[1]
    properties, models = discover(root)
    modules = list(dict.fromkeys(["Workflow.Declarative.CLI"] +
                                [p[0] for p in properties] + [m[0] for m in models]))
    # Scoped compilation adds no proof attempts: property/model exports contain definitions.
    build = subprocess.run(["lake", "build", *modules], cwd=root)
    if build.returncode:
        return build.returncode
    output = root / "output"
    output.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="discovery.", dir=output))
    driver = folder / "Bootstrap.lean"
    driver.write_text(bootstrap(properties, models))
    print(f"Discovery bootstrap: {driver}", flush=True)
    return subprocess.run(["lake", "env", "lean", "--run", str(driver), *args], cwd=root).returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        print(f"Property discovery: {error}", file=sys.stderr)
        raise SystemExit(2)

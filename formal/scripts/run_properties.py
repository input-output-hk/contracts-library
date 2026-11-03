#!/usr/bin/env python3
"""Discover selected property runs, then compile only their actual model exports."""

import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def module_name(root, path):
    parts = path.relative_to(root).with_suffix("").parts
    if not all(re.fullmatch(r"[A-Z][A-Za-z0-9_]*", part) for part in parts):
        raise ValueError(f"invalid Lean module path: {path}")
    return ".".join(parts)


def candidates(root):
    entries, errors = [], []
    for path in sorted((root / "Formal/Properties").rglob("Run.lean")):
        metadata = path.with_name("metadata.json")
        try:
            identity = json.loads(metadata.read_text())["identity"]["id"]
            if not isinstance(identity, str) or not identity.strip():
                raise ValueError("missing property ID")
            entries.append((identity, path))
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f"{metadata}: {error}")
    return entries, errors


def selection(args, known):
    requested, file_names = [], []
    for index, value in enumerate(args):
        if value in ("--check", "--checks-file"):
            if index + 1 == len(args) or args[index + 1].startswith("--"):
                raise ValueError(f"{value} requires a value")
            (requested if value == "--check" else file_names).append(args[index + 1])
    if len(file_names) > 1:
        raise ValueError("--checks-file may be supplied only once")
    if requested and file_names:
        raise ValueError("--check and --checks-file cannot be combined")
    source = None
    if file_names:
        source = Path(file_names[0]).read_bytes().decode("utf-8")
        values = json.loads(source)
        if not isinstance(values, dict):
            raise ValueError("selection file must contain property IDs and booleans")
        for name, enabled in values.items():
            if name not in known:
                raise ValueError(f"unknown property: {name}")
            if type(enabled) is not bool:
                raise ValueError(f"{name}: selection must be true or false")
        requested = [name for name, enabled in values.items() if enabled]
    elif not requested:
        requested = list(known)
    for name in requested:
        if name not in known:
            raise ValueError(f"unknown property: {name}")
    return [name for name in known if name in requested], source


def properties_for(root, entries, selected):
    properties, ids = [], []
    for identity, path in entries:
        if identity not in selected:
            continue
        if identity in ids:
            raise ValueError(f"duplicate property ID: {identity}")
        ids.append(identity)
        definition = path.with_name("Definition.lean")
        if not definition.is_file():
            raise ValueError(f"{path}: requires Definition.lean")
        module = module_name(root, path)
        properties.append((module, module.removesuffix(".Run") + ".run",
                           module_name(root, definition), str(path.with_name("metadata.json").relative_to(root))))
    return properties


def models_for(root, identities):
    models = []
    for identity in dict.fromkeys(identities):
        match = re.fullmatch(r"TxM-([0-9]+)", identity)
        if not match:
            raise ValueError(f"invalid model ID: {identity}")
        stem = "TxM" + match[1]
        path = root / "Formal/TxModels/Definitions" / (stem + ".lean")
        if not path.is_file():
            raise ValueError(f"unknown model: {identity}")
        if not re.search(
                r"^[ \t]*def runnable\s*:\s*(?:Formal\.TxModels\.)?Runnable\s*:=",
                path.read_text(), re.MULTILINE):
            raise ValueError(f"{identity}: missing runnable export")
        models.append((module_name(root, path), f"Formal.TxModels.{stem}.runnable"))
    return models


def property_entries(properties):
    return "#[" + ",\n      ".join(
        "{ run := " + name + ", runModule := " + quoted(module) +
        ", definitionModule := " + quoted(definition) + ", metadataPath := " + quoted(metadata) + " }"
        for module, name, definition, metadata in properties) + "]"


def imports(properties, models=()):
    return list(dict.fromkeys([p[0] for p in properties] + [m[0] for m in models]))


def plan_source(properties):
    modules = ["Workflow.Declarative.Discovery"] + imports(properties)
    return "\n".join("import " + name for name in modules) + \
        "\n\ndef main : IO UInt32 :=\n  Workflow.Declarative.Discovery.describe\n    " + \
        property_entries(properties) + "\n"


def bootstrap(properties, models, known=(), snapshot=None, index=None):
    modules = ["Workflow.Declarative.CLI"] + imports(properties, models)
    model_entries = "#[" + ",\n      ".join(
        "{ moduleName := " + quoted(module) + ", runnable := " + name + " }"
        for module, name in models) + "]"
    optional = lambda path: "(some " + quoted(str(path)) + ")" if path else "none"
    return "\n".join("import " + name for name in modules) + \
        "\n\ndef main (args : List String) : IO UInt32 :=\n  Workflow.Declarative.main\n    " + \
        property_entries(properties) + "\n    " + model_entries + " args\n    #[" + ", ".join(map(quoted, known)) + "]\n    " + \
        optional(snapshot) + "\n    " + optional(index) + "\n"


def preparation_budget(args):
    value = 300000
    for index, argument in enumerate(args):
        if argument == "--timeout-ms":
            value = int(args[index + 1])
            if value <= 0:
                raise ValueError("--timeout-ms requires positive milliseconds")
    return max(value, 30000) / 1000


def main(args):
    root = Path(__file__).resolve().parents[1]
    output = root / "output"
    output.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="discovery.", dir=output))
    index_path = folder / "index.json"
    record = {"args": args, "cwd": str(root), "state": "preparing", "commands": []}
    save = lambda: index_path.write_text(json.dumps(record, indent=2) + "\n")
    save()
    try:
        deadline = time.monotonic() + preparation_budget(args)

        def step(label, command):
            entry = {"command": command, "stdout": str(folder / (label + ".stdout.log")),
                     "stderr": str(folder / (label + ".stderr.log"))}
            record["commands"].append(entry)
            save()
            with subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, start_new_session=True) as process:
                try:
                    stdout, stderr = process.communicate(timeout=max(0.001, deadline - time.monotonic()))
                except subprocess.TimeoutExpired as error:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    stdout, stderr = process.communicate()
                    Path(entry["stdout"]).write_text(stdout)
                    Path(entry["stderr"]).write_text(stderr)
                    entry["state"] = "timedOut"
                    save()
                    raise ValueError("selected-check preparation timed out") from error
                exit_code = process.returncode
            Path(entry["stdout"]).write_text(stdout)
            Path(entry["stderr"]).write_text(stderr)
            entry["exit_code"] = exit_code
            save()
            if exit_code:
                print(stdout, file=sys.stderr)
                print(stderr, file=sys.stderr)
                raise ValueError(f"{label} failed; see retained preparation logs")
            return stdout

        entries, metadata_errors = candidates(root)
        known = list(dict.fromkeys(p[0] for p in entries))
        selected, selection_source = selection(args, known)
        if metadata_errors and not any(flag in args for flag in ["--check", "--checks-file"]):
            raise ValueError("; ".join(metadata_errors))
        if not known:
            raise ValueError("no property Run.lean files discovered")
        properties = properties_for(root, entries, selected)
        snapshot = None
        if selection_source is not None:
            snapshot = folder / "checks.json"
            snapshot.write_bytes(selection_source.encode("utf-8"))
        record.update({"known_properties": known, "selected_properties": selected,
                       "selection_snapshot": str(snapshot) if snapshot else None,
                       "ignored_metadata_errors": metadata_errors})
        planner = folder / "Plan.lean"
        planner.write_text(plan_source(properties))
        modules = ["Workflow.Declarative.Discovery"] + imports(properties)
        step("properties-build", ["lake", "build", *dict.fromkeys(modules)])
        manifest = json.loads(step("models-plan", ["lake", "env", "lean", "--run", str(planner)]))
        record["selected_models"] = manifest
        models = models_for(root, manifest["models"])
        modules = ["Workflow.Declarative.CLI"] + imports(properties, models)
        step("models-build", ["lake", "build", *dict.fromkeys(modules)])
        driver = folder / "Bootstrap.lean"
        driver.write_text(bootstrap(properties, models, known, snapshot, index_path))
        sources = [root / p[3] for p in properties]
        sources += [root / (p[2].replace(".", "/") + ".lean") for p in properties]
        sources += [root / (p[0].replace(".", "/") + ".lean") for p in properties + models]
        record["source_hashes"] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in sources}
        record["state"] = "ready"
        save()
        result = subprocess.run(["lake", "env", "lean", "--run", str(driver), *args], cwd=root)
        record.update({"state": "finished", "exit_code": result.returncode})
        save()
        return result.returncode
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        record.update({"state": "failed", "error": str(error)})
        save()
        print(f"Could not prepare selected checks: {error}\nPreparation evidence: {index_path}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

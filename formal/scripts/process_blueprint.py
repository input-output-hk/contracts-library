#!/usr/bin/env python3
"""Generate Lean types, copy compiled CBOR, or generate selected candidate checks.

Type generation supports Plutus V3. --check selects otherPurpose,
malformedRedeemer, or returnDatum without transaction shapes.
See formal/docs/BLUEPRINT.md for supported inputs and output files.

The blueprint translator is extracted from sayyadirfanali's universal-checks
branch at 99a5734f0e036b6abfb4c3f121a298e35fa2eff6 (fork PR #44).
"""

import argparse
import hashlib
import json
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

TRANSLATION = """
Schema form                         Lean type              Encoding
integer                             Int                    Data.I
bytes (ByteArray, hashes, ids)      ByteString             Data.B
Data, or an empty schema            Data                   as is
list with `items: T`                List T                 Data.List
list with `items: [T1, ..]`         T1 × .. (a tuple)      Data.List [..]
map with keys K, values V           List (K × V)           Data.Map
Option<T>                           Option T               Some = Constr 0 [x], None = Constr 1 []
Bool                                Bool                   False = Constr 0 [], True = Constr 1 []
cardano/address/Credential          Credential             (CardanoLedgerApi.V3)
cardano/address/StakeCredential     StakingCredential      (CardanoLedgerApi.V3)
cardano/address/Address             Address                (CardanoLedgerApi.V3)
cardano/transaction/OutputReference TxOutRef               (CardanoLedgerApi.V3)
one constructor                     structure              Constr index [fields]
several constructors                inductive              Constr index [fields]
a definition that refers to itself  Data                   as is (a warning comment is written)
"""

# Lean keywords and names that cannot be used as field or constructor names.
LEAN_RESERVED = {
    "abbrev", "at", "attribute", "axiom", "break", "by", "calc", "catch", "class", "continue",
    "decreasing_by", "def", "deriving", "do", "else", "end", "example", "exists", "extends",
    "finally", "for", "forall", "from", "fun", "have", "if", "import", "in", "inductive",
    "instance", "let", "local", "macro", "match", "mk", "mut", "mutual", "namespace",
    "noncomputable", "nomatch", "nofun", "notation", "opaque", "open", "partial", "private",
    "protected", "rec", "return", "section", "set_option", "show", "sorry", "structure",
    "syntax", "termination_by", "then", "theorem", "try", "universe", "unless", "unsafe",
    "variable", "where", "with", "Prop", "Sort", "Type",
}

# Cardano types reused from CardanoLedgerApi.V3, with the constructor layout their IsData
# instances use. A mapping applies only when the blueprint's schema has exactly this layout
# (index and arity of every constructor); otherwise the type is generated from its schema.
LEDGER_TYPES = {
    "cardano/address/Credential": ("Credential", [(0, 1), (1, 1)]),
    "cardano/address/StakeCredential": ("StakingCredential", [(0, 1), (1, 3)]),
    "cardano/address/Address": ("Address", [(0, 2)]),
    "cardano/transaction/OutputReference": ("TxOutRef", [(0, 2)]),
}


class ExtractError(Exception):
    pass


def camel(segment):
    """`poll_effect` -> `PollEffect`, `types` -> `Types`; other characters are dropped."""
    parts = re.split(r"[^A-Za-z0-9]+", segment)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def ident(name, fallback):
    """A Lean identifier for a field or constructor title; reserved words are «quoted»."""
    s = re.sub(r"[^A-Za-z0-9_]", "_", name or "") or fallback
    if s[0].isdigit():
        s = "_" + s
    return f"«{s}»" if s in LEAN_RESERVED else s


class Translator:
    def __init__(self, definitions):
        self.defs = definitions
        self.named = {}       # definition key -> Lean type name, for generated types
        self.order = []       # definition keys, dependencies first
        self.decls = {}       # definition key -> (kind, constructors)
        self.visiting = []    # keys being translated (cycle detection)
        self.warnings = []

    # ---- schema resolution ----

    def resolve(self, schema):
        """Return (key, schema) with `$ref` followed; key is None for inline schemas."""
        if "$ref" in schema:
            ref = schema["$ref"]
            if not ref.startswith("#/definitions/"):
                raise ExtractError(f"unsupported reference {ref}")
            key = ref[len("#/definitions/"):].replace("~1", "/").replace("~0", "~")
            if key not in self.defs:
                raise ExtractError(f"missing definition {key}")
            return key, self.defs[key]
        return None, schema

    # ---- types ----

    def ty(self, schema, where):
        """Translate a schema into a type description used by `lean_type`, `enc` and `dec`."""
        key, s = self.resolve(schema)
        if key in LEDGER_TYPES and self.ledger_layout_matches(s, LEDGER_TYPES[key][1]):
            return ("ledger", LEDGER_TYPES[key][0])
        if key is not None and key in self.visiting:
            self.warnings.append(f"{key} refers to itself; translated as Data in {where}")
            return ("data",)
        if "anyOf" in s:
            ctors = s["anyOf"]
            if self.is_option(key, ctors):
                return ("option", self.ty(ctors[0]["fields"][0], where))
            if self.is_bool(key, ctors):
                return ("bool",)
            return ("named", self.declare(key, s, where))
        dt = s.get("dataType")
        if dt is None:
            if set(s) - {"title", "description", "$comment"}:
                raise ExtractError(f"unknown schema form in {where}: {json.dumps(s)[:200]}")
            return ("data",)
        if dt == "integer":
            return ("int",)
        if dt == "bytes":
            return ("bytes",)
        if dt == "list":
            items = s.get("items")
            if isinstance(items, list):
                return ("tuple", [self.ty(i, where) for i in items])
            if items is None:
                return ("list", ("data",))
            return ("list", self.ty(items, where))
        if dt == "map":
            k = self.ty(s["keys"], where) if "keys" in s else ("data",)
            v = self.ty(s["values"], where) if "values" in s else ("data",)
            return ("map", k, v)
        if dt == "constructor":
            return ("named", self.declare(key, {"anyOf": [s]}, where))
        raise ExtractError(f"unknown dataType {dt!r} in {where}")

    @staticmethod
    def ledger_layout_matches(s, layout):
        ctors = s.get("anyOf")
        if not ctors:
            return False
        got = sorted((c.get("index"), len(c.get("fields", []))) for c in ctors)
        return got == sorted(layout)

    @staticmethod
    def is_option(key, ctors):
        return (key or "").startswith("Option<") and len(ctors) == 2 \
            and ctors[0].get("index") == 0 and len(ctors[0].get("fields", [])) == 1 \
            and ctors[1].get("index") == 1 and not ctors[1].get("fields")

    @staticmethod
    def is_bool(key, ctors):
        return key == "Bool" and [(c.get("index"), len(c.get("fields", []))) for c in ctors] == [(0, 0), (1, 0)]

    def lean_name(self, key):
        """`vesting/types/VestingDatum` -> `Vesting.Types.VestingDatum`; generics become suffixes."""
        base, _, generic = key.partition("<")
        segs = [camel(p) for p in base.split("/")]
        if generic:
            segs[-1] += "_" + camel(generic.rstrip(">"))
        if len(segs) == 1:
            segs.insert(0, "Types")
        return ".".join(segs)

    def declare(self, key, s, where):
        if key is None:
            raise ExtractError(f"inline constructor type in {where}; only named ones are supported")
        if key in self.named:
            return self.named[key]
        name = self.lean_name(key)
        self.visiting.append(key)
        ctors = []
        for i, c in enumerate(s["anyOf"]):
            if c.get("dataType") != "constructor":
                raise ExtractError(f"non-constructor alternative in {key}")
            fields = []
            for j, f in enumerate(c.get("fields", [])):
                fields.append((ident(f.get("title"), f"field{j}"), self.ty(f, f"{key}.{f.get('title', j)}")))
            ctor_name = ident(c.get("title"), f"Ctor{i}")
            ctors.append((ctor_name, c["index"], fields))
        self.visiting.pop()
        kind = "structure" if len(ctors) == 1 else "inductive"
        if name in self.named.values():
            raise ExtractError(f"two definitions translate to the Lean name {name}")
        self.named[key] = name
        self.decls[key] = (kind, ctors)
        self.order.append(key)
        return name


# ---- Lean text ----

def lean_type(t):
    tag = t[0]
    if tag == "int":
        return "Int"
    if tag == "bytes":
        return "ByteString"
    if tag == "data":
        return "Data"
    if tag == "bool":
        return "Bool"
    if tag in ("ledger", "named"):
        return t[1]
    if tag == "list":
        return f"List ({lean_type(t[1])})"
    if tag == "map":
        return f"List ({lean_type(t[1])} × {lean_type(t[2])})"
    if tag == "option":
        return f"Option ({lean_type(t[1])})"
    if tag == "tuple":
        return "(" + " × ".join(lean_type(x) for x in t[1]) + ")"
    raise AssertionError(t)


class Fresh:
    def __init__(self):
        self.n = 0

    def __call__(self, base="v"):
        self.n += 1
        return f"{base}{self.n}"


def tuple_proj(e, i, n):
    """Projection `e.2.2.1` of component i of an n-tuple (Lean products nest to the right)."""
    if n == 1:
        return e
    path = ".2" * i + (".1" if i < n - 1 else "")
    return f"({e}){path}"


def enc(t, e, fresh):
    """A Lean expression of type Data encoding `e : lean_type t`."""
    tag = t[0]
    if tag == "int":
        return f"Data.I {e}"
    if tag == "bytes":
        return f"Data.B {e}"
    if tag == "data":
        return e
    if tag in ("ledger", "named"):
        return f"IsData.toData {e}"
    if tag == "bool":
        return f"(if {e} then Data.Constr 1 [] else Data.Constr 0 [])"
    if tag == "option":
        v = fresh()
        return f"(match {e} with | some {v} => Data.Constr 0 [{enc(t[1], v, fresh)}] | none => Data.Constr 1 [])"
    if tag == "list":
        v = fresh()
        return f"Data.List (({e}).map (fun {v} => {enc(t[1], v, fresh)}))"
    if tag == "map":
        v = fresh()
        return f"Data.Map (({e}).map (fun {v} => ({enc(t[1], v + '.1', fresh)}, {enc(t[2], v + '.2', fresh)})))"
    if tag == "tuple":
        n = len(t[1])
        return "Data.List [" + ", ".join(enc(x, tuple_proj(e, i, n), fresh) for i, x in enumerate(t[1])) + "]"
    raise AssertionError(t)


def dec(t, d, fresh):
    """A Lean expression of type Option (lean_type t) decoding `d : Data`."""
    tag = t[0]
    if tag == "int":
        v = fresh("i")
        return f"(match {d} with | Data.I {v} => some {v} | _ => none)"
    if tag == "bytes":
        v = fresh("b")
        return f"(match {d} with | Data.B {v} => some {v} | _ => none)"
    if tag == "data":
        return f"(some {d})"
    if tag in ("ledger", "named"):
        return f"(IsData.fromData {d} : Option {t[1]})"
    if tag == "bool":
        return (f"(match {d} with | Data.Constr 0 [] => some false "
                f"| Data.Constr 1 [] => some true | _ => none)")
    if tag == "option":
        v = fresh()
        return (f"(match {d} with | Data.Constr 0 [{v}] => ({dec(t[1], v, fresh)}).map some "
                f"| Data.Constr 1 [] => some none | _ => none)")
    if tag == "list":
        v, xs = fresh(), fresh("xs")
        return f"(match {d} with | Data.List {xs} => {xs}.mapM (fun {v} => {dec(t[1], v, fresh)}) | _ => none)"
    if tag == "map":
        p, ps, k, w = fresh("p"), fresh("ps"), fresh("k"), fresh("w")
        return (f"(match {d} with | Data.Map {ps} => {ps}.mapM (fun {p} => do "
                f"let {k} ← {dec(t[1], p + '.1', fresh)}; let {w} ← {dec(t[2], p + '.2', fresh)}; "
                f"pure ({k}, {w})) | _ => none)")
    if tag == "tuple":
        ds = [fresh("d") for _ in t[1]]
        vs = [fresh("t") for _ in t[1]]
        binds = "; ".join(f"let {v} ← {dec(x, di, fresh)}" for x, di, v in zip(t[1], ds, vs))
        return (f"(match {d} with | Data.List [{', '.join(ds)}] => (do {binds}; "
                f"pure ({', '.join(vs)})) | _ => none)")
    raise AssertionError(t)


def emit_decl(name, kind, ctors):
    fresh = Fresh()
    out = []
    if kind == "structure":
        (ctor, index, fields), = ctors
        out.append(f"structure {name} where")
        for f, t in fields:
            out.append(f"  {f} : {lean_type(t)}")
        if not fields:
            out[-1] += " mk ::"
        out.append("")
        out.append(f"instance : IsData {name} where")
        items = ", ".join(enc(t, f"x.{f}", fresh) for f, t in fields)
        out.append(f"  toData {'x' if fields else '_'} := Data.Constr {index} [{items}]")
        ds = [f"d{j}" for j in range(len(fields))]
        out.append("  fromData")
        if fields:
            out.append(f"    | Data.Constr {index} [{', '.join(ds)}] => do")
            for (f, t), dj, j in zip(fields, ds, range(len(fields))):
                out.append(f"        let a{j} ← {dec(t, dj, fresh)}")
            out.append(f"        pure ({name}.mk {' '.join(f'a{j}' for j in range(len(fields)))})")
        else:
            out.append(f"    | Data.Constr {index} [] => some {name}.mk")
        out.append("    | _ => none")
    else:
        out.append(f"inductive {name} where")
        for ctor, index, fields in ctors:
            args = " ".join(f"({f} : {lean_type(t)})" for f, t in fields)
            out.append(f"  | {ctor}{(' ' + args) if args else ''}")
        out.append("")
        out.append(f"instance : IsData {name} where")
        out.append("  toData")
        for ctor, index, fields in ctors:
            vs = [f"a{j}" for j in range(len(fields))]
            pat = f"{name}.{ctor}" + "".join(" " + v for v in vs)
            items = ", ".join(enc(t, v, fresh) for (f, t), v in zip(fields, vs))
            out.append(f"    | {pat} => Data.Constr {index} [{items}]")
        out.append("  fromData")
        for ctor, index, fields in ctors:
            ds = [f"d{j}" for j in range(len(fields))]
            if fields:
                out.append(f"    | Data.Constr {index} [{', '.join(ds)}] => do")
                for (f, t), dj, j in zip(fields, ds, range(len(fields))):
                    out.append(f"        let a{j} ← {dec(t, dj, fresh)}")
                out.append(f"        pure ({name}.{ctor} {' '.join(f'a{j}' for j in range(len(fields)))})")
            else:
                out.append(f"    | Data.Constr {index} [] => some {name}.{ctor}")
        out.append("    | _ => none")
    return out


# ---- validators ----

def find_entries(bp, name):
    """Blueprint titles are `module.validator.handler`; `name` is `module.validator` or `validator`."""
    def head(v):
        return ".".join(v["title"].split(".")[:2])
    entries = bp.get("validators", [])
    heads = sorted({head(v) for v in entries
                    if head(v) == name or ("." not in name and head(v).split(".")[1] == name)})
    if not heads:
        raise ExtractError(f"no validator `{name}` in the blueprint")
    if len(heads) > 1:
        raise ExtractError(f"`{name}` is ambiguous: {', '.join(heads)}")
    return [v for v in entries if head(v) == heads[0]]


def cbor_path_of(entries, scripts_dir):
    """`<scripts>/<module>.<validator>.cbor`, with `/` in the module replaced by `.`."""
    module, validator = entries[0]["title"].split(".")[:2]
    return f"{scripts_dir}/{module.replace('/', '.')}.{validator}.cbor"


def compiled_code(entries):
    """The compiledCode shared by all handlers of one validator."""
    head = ".".join(entries[0]["title"].split(".")[:2])
    codes = {e.get("compiledCode") for e in entries}
    if len(codes) != 1:
        raise ExtractError(f"handlers of `{head}` have different compiled code")
    return entries[0]["compiledCode"]


def module_prefix(folder):
    """`Formal/Vesting/Linear/Blueprint` -> `Formal.Vesting.Linear.Blueprint`."""
    parts = [p for p in Path(folder).parts if p not in ("", ".")]
    if not parts or parts[0] != "Formal":
        raise ExtractError(f"the folder `{folder}` is not under Formal/; Lean module names follow the path")
    for p in parts:
        if not re.fullmatch(r"[A-Z][A-Za-z0-9_]*", p):
            raise ExtractError(f"the folder name `{p}` in `{folder}` is not a Lean module name")
    return ".".join(parts)


PURPOSES = ["spend", "mint", "withdraw", "publish", "vote", "propose"]


@dataclass
class Handler:
    purpose: str
    redeemer_kind: str          # constructors | integer | bytes | list | map | any
    redeemer_ctors: list        # [(Lean constructor, index, [(field, type)])] when a named type, else []
    redeemer_type: object       # the type description, or None without a redeemer schema


@dataclass
class ValidatorInfo:
    head: str                   # `module.validator`
    prefix: str                 # module prefix and namespace, e.g. `Formal.Vesting.Linear.Blueprint`
    origin: str                 # the blueprint entry and compiler, for the files' first line
    handlers: list              # [Handler], without the `else` fallback
    has_params: bool
    datum_kind: str             # kind of the spend datum, or "none" without a spend handler
    datum_ctors: list           # constructors of the spend datum when a named type, else []
    datum_type: object          # the spend datum's type description, or None
    translator: object          # for the fields of named types
    warnings: list


def redeemer_kind(t):
    """The top-level form of a datum or redeemer type, which decides its malformed forms."""
    return {"int": "integer", "bytes": "bytes", "list": "list", "tuple": "list",
            "map": "map", "data": "any"}.get(t[0], "constructors")


def generate(bp, name, prefix, scripts_dir, inline_script=False):
    """Pass 1: (the lines of Types.lean without the closing `end`, ValidatorInfo)."""
    entries = find_entries(bp, name)
    head = ".".join(entries[0]["title"].split(".")[:2])
    module, validator = head.split(".")
    compiled_code(entries)
    params = entries[0].get("parameters", [])
    tr = Translator(bp.get("definitions", {}))

    handlers = []
    for e in entries:
        purpose = e["title"].split(".")[-1]
        datum = tr.ty(e["datum"]["schema"], f"{purpose} datum") if e.get("datum") else None
        redeemer = tr.ty(e["redeemer"]["schema"], f"{purpose} redeemer") if e.get("redeemer") else None
        handlers.append((purpose, datum, redeemer))
    ptys = [(ident(p.get("title"), f"param{j}"), tr.ty(p["schema"], f"parameter {p.get('title', j)}"))
            for j, p in enumerate(params)]

    cbor_path = cbor_path_of(entries, scripts_dir)
    compiler = bp.get("preamble", {}).get("compiler", {})
    version = bp.get("preamble", {}).get("plutusVersion", "v3")
    if version != "v3":
        raise ExtractError(f"plutusVersion {version} is not supported")
    origin = f"the blueprint entry `{head}` ({compiler.get('name', '?')} {compiler.get('version', '?')})"

    L = []
    L.append(f"-- Generated by process_blueprint.py from {origin}. Do not edit; regenerate.")
    L += ["import PlutusCore.UPLC", "import CardanoLedgerApi", "import Formal.Universal.Properties", ""]
    L.append(f"namespace {prefix}")
    L.append("")
    L += ["open PlutusCore.Data (Data)",
          "open PlutusCore.ByteString (ByteString)",
          "open PlutusCore.UPLC.Term (Term Const Program)",
          "open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)",
          "open CardanoLedgerApi.IsData.Class (IsData toTerm)",
          "open CardanoLedgerApi.V3 (Address Credential StakingCredential ScriptContext TxOutRef)",
          ""]
    for w in tr.warnings:
        L.append(f"-- WARNING: {w}")
    if tr.warnings:
        L.append("")

    L.append("/-! ## Types -/")
    L.append("")
    for key in tr.order:
        kind, ctors = tr.decls[key]
        L.append(f"/-- `{key}` -/")
        L += emit_decl(tr.named[key], kind, ctors)
        L.append("")

    L.append("/-! ## Handlers -/")
    L.append("")
    declared = [p for p, _, _ in handlers if p != "else"]
    L.append(f"/-- Purposes with a handler in the blueprint (the `else` fallback is not listed). -/")
    L.append("def handlers : List String := [" + ", ".join(f'"{p}"' for p in declared) + "]")
    L.append("")
    for purpose, datum, redeemer in handlers:
        if purpose == "else":
            continue
        P = camel(purpose)
        if datum is not None:
            L.append(f"abbrev {P}Datum := {lean_type(datum)}")
        if redeemer is not None:
            L.append(f"abbrev {P}Redeemer := {lean_type(redeemer)}")
    L.append("")

    L.append("/-! ## Parameters and script -/")
    L.append("")
    fresh = Fresh()
    if ptys:
        L.append("/-- Parameters, in the order the script takes them. -/")
        L.append("structure Params where")
        for f, t in ptys:
            L.append(f"  {f} : {lean_type(t)}")
        L.append("")
        L.append("/-- The script's arguments: the parameters, then the script context. -/")
        L.append("def args (p : Params) (ctx : ScriptContext) : List Term :=")
        items = [f"Term.Const (Const.Data ({enc(t, 'p.' + f, fresh)}))" for f, t in ptys] + ["toTerm ctx"]
        L.append("  [" + ",\n   ".join(items) + "]")
        sig, call = "(p : Params) (ctx : ScriptContext)", "(args p ctx)"
    else:
        L.append("/-- The script's arguments: the script context only (no parameters). -/")
        L.append("def args (ctx : ScriptContext) : List Term := [toTerm ctx]")
        sig, call = "(ctx : ScriptContext)", "(args ctx)"
    L.append("")
    # `#import_uplc` may declare at the root namespace, so the name carries the validator's.
    script = camel(validator)[:1].lower() + camel(validator)[1:] + "Script"
    if inline_script:
        L += [f"abbrev {script} : PlutusCore.UPLC.PlutusScript.PlutusScript :=",
              f'  ⟨.PlutusV3, singleCborEncodedScriptFromHexM "{compiled_code(entries)}"⟩']
    else:
        L.append(f'#import_uplc {script} PlutusV3 single_cbor_hex "{cbor_path}"')
    L.append("")
    L.append(f"def program : Program := {script}.script")
    L.append("")
    L.append(f'/-- The script hash recorded in the blueprint (hex). -/')
    L.append(f'def scriptHashHex : String := "{entries[0].get("hash", "")}"')
    L.append("")
    L.append("/-- The script accepts within `fuel` steps. -/")
    L.append(f"def accepts (fuel : Nat) {sig} : Prop :=")
    L.append(f"  cekExecuteProgram program {call} fuel = .Halt (.VCon Const.Unit)")
    L.append("")
    L.append("/-- The script genuinely fails within `fuel` steps (running out of steps is not a failure). -/")
    L.append(f"def rejects (fuel : Nat) {sig} : Prop :=")
    L.append(f"  Formal.Universal.Properties.rejectedWithin program {call} fuel")
    L.append("")

    def ctors_of(t):
        if t is None or t[0] != "named":
            return []
        key = next(k for k, n in tr.named.items() if n == t[1])
        kind, ctors = tr.decls[key]
        # The Lean constructor: `T.mk` for a structure, `T.Ctor` for an inductive.
        return [(f"{t[1]}.{'mk' if kind == 'structure' else c}", i, fs) for c, i, fs in ctors]

    datum_kind, datum_ctors, datum_type = "none", [], None
    infos = []
    for purpose, datum, redeemer in handlers:
        if purpose == "else":
            continue
        if purpose not in PURPOSES:
            raise ExtractError(f"unknown handler purpose `{purpose}`")
        kind = redeemer_kind(redeemer) if redeemer is not None else "any"
        infos.append(Handler(purpose, kind, ctors_of(redeemer), redeemer))
        if purpose == "spend":
            datum_kind = redeemer_kind(datum) if datum is not None else "any"
            datum_ctors, datum_type = ctors_of(datum), datum
    info = ValidatorInfo(head, prefix, origin, infos, bool(ptys), datum_kind, datum_ctors,
                         datum_type, tr, tr.warnings)
    return L, info

# Per-purpose context builders and malformed-redeemer helpers from the source cited above.
EVERY = {"spend": "EverySpend", "mint": "EveryMint", "withdraw": "EveryWithdraw",
         "publish": "EveryPublish", "vote": "EveryVote", "propose": "EveryPropose"}

NOUN = {"spend": "spend", "mint": "mint", "withdraw": "withdrawal", "publish": "certificate",
        "vote": "vote", "propose": "proposal"}


def other_purpose_checks(info):
    """Extract UP-001 with its original quantifiers and negated acceptance claim."""
    declared = {h.purpose for h in info.handlers}
    undeclared = [p for p in PURPOSES if p not in declared]
    binder = " (p : Params)" if info.has_params else ""
    params = " p" if info.has_params else ""
    lines = [f"-- Generated by process_blueprint.py from {info.origin}. Do not edit; regenerate.",
             "import Blaster", "import Formal.Universal.Properties", f"import {info.prefix}.Types",
             "", "set_option Elab.async false", "", f"namespace {info.prefix}", "",
             "open PlutusCore.Data (Data)", "open Formal.Universal.Properties", "",
             "/-! UP-001: no success within ledgerFuel for undeclared purposes.",
             "The full TxInfo, redeemer, and purpose fields are variables.",
             "Fuel exhaustion satisfies this claim; it does not establish an explicit error.",
             "-/", ""]
    if not undeclared:
        lines += ["-- All purposes have handlers: no UP-001 goals apply.", ""]
    for purpose in undeclared:
        ctx = EVERY[purpose]
        lines += [f"/-- No {NOUN[purpose]} is accepted within ledgerFuel: no {purpose} handler. -/",
                  f"theorem otherPurpose_{purpose}{binder} :",
                  f"    ∀ (r : Data) (t : {ctx}),",
                  f"      ¬ accepts ledgerFuel{params} ({ctx}.ctx t r) := by blaster", ""]
    return lines + [f"end {info.prefix}"]


FORMS = {"int": ("an integer", "n", "Int", "Data.I n"),
         "bytes": ("a byte string", "b", "ByteString", "Data.B b"),
         "list": ("a list", "l", "List Data", "Data.List l"),
         "map": ("a map", "m", "List (Data × Data)", "Data.Map m")}

MALFORMED = {"constructors": ["int", "bytes", "list", "map"], "integer": ["bytes", "list", "map"],
             "bytes": ["int", "list", "map"], "list": ["int", "bytes", "map"],
             "map": ["int", "bytes", "list"], "any": []}

class Terms:
    """Data terms for well-formed values of a type, with their variables. Every leaf (integer,
    byte string, credential, ...) is a variable; every list and map is empty, so that the script
    never walks a list of unknown length; an `Option` or a sum that holds a list somewhere is its
    first alternative, for the same reason. A type with no list anywhere is one typed variable."""

    def __init__(self, tr):
        self.tr = tr
        self.by_name = {n: k for k, n in tr.named.items()}
        self.n = 0
        self.binders = []

    def var(self, ty):
        self.n += 1
        v = f"x{self.n}"
        self.binders.append(f"({v} : {ty})")
        return v

    def has_list(self, t, seen=()):
        tag = t[0]
        if tag in ("list", "map"):
            return True
        if tag == "option":
            return self.has_list(t[1], seen)
        if tag == "tuple":
            return any(self.has_list(x, seen) for x in t[1])
        if tag == "named":
            key = self.by_name[t[1]]
            if key in seen:
                return True
            _, ctors = self.tr.decls[key]
            return any(self.has_list(ft, seen + (key,)) for _, _, fs in ctors for _, ft in fs)
        return False

    def term(self, t):
        tag = t[0]
        if tag in ("list", "map"):
            return "(Data.List [])" if tag == "list" else "(Data.Map [])"
        if not self.has_list(t):
            return f"({enc(t, self.var(lean_type(t)), Fresh())})"
        if tag == "option":
            return "(Data.Constr 1 [])"
        if tag == "tuple":
            return "(Data.List [" + ", ".join(self.term(x) for x in t[1]) + "])"
        _, ctors = self.tr.decls[self.by_name[t[1]]]
        _, index, fields = ctors[0]
        return self.ctor(index, fields)

    def ctor(self, index, fields, replace=None):
        """`Data.Constr index [fields]`, with field j replaced by `replace[j]` when given."""
        items = [(replace or {}).get(j) or self.term(ft) for j, (_, ft) in enumerate(fields)]
        return f"(Data.Constr {index} [{', '.join(items)}])"

    def wrong(self, t):
        """A Data term of the wrong form for a field of type t, or None for a Data field."""
        if t[0] == "data":
            return None
        if t[0] == "int":
            return f"(Data.B {self.var('ByteString')})"
        return f"(Data.I {self.var('Int')})"

def short(ctor):
    """`Sale.SaleRedeemer.Buy` -> `Buy`; `T.mk` -> `T`'s last segment."""
    return (ctor.split(".")[-2] if ctor.endswith(".mk") else ctor.split(".")[-1]).strip("«»")

def plain(field):
    return field.strip("«»")

def malformed(tr, kind, ctors, first_var, fixed=False):
    """[(suffix, text, binders, Data term)]: the ways a value of a type of this kind and these
    constructors fails to decode, each with its variables. With `fixed`, a constructor with an
    unknown index has the first constructor's fields instead of a list of variable length."""
    out = []
    for form in MALFORMED[kind]:
        text, v, ty, term = FORMS[form]
        out.append((f"wrongForm_{form}", f"{text} instead of the declared type", [f"({v} : {ty})"], f"({term})"))
    if kind == "constructors" and ctors:
        declared = {index for _, index, _ in ctors}
        unknown = [i for i in range(len(declared) + 2) if i not in declared][:2]
        for idx in unknown:
            if fixed:
                w = Terms(tr)
                w.n = first_var
                term = w.ctor(idx, ctors[0][2])
                out.append((f"unknownIndex{idx}", f"a constructor with the unknown index {idx}", w.binders, term))
            else:
                out.append((f"unknownIndex{idx}", f"a constructor with the unknown index {idx}",
                            ["(fs : List Data)"], f"(Data.Constr {idx} fs)"))
        for ctor, index, fields in ctors:
            c = short(ctor)
            w = Terms(tr)
            w.n = first_var
            items = [w.term(ft) for _, ft in fields]
            extra = w.var("Data")
            out.append((f"{c}_extraField", f"{c} with an extra field", w.binders,
                        f"(Data.Constr {index} [{', '.join(items + [extra])}])"))
            if fields:
                w = Terms(tr)
                w.n = first_var
                items = [w.term(ft) for _, ft in fields[:-1]]
                out.append((f"{c}_missingField", f"{c} without its last field", w.binders,
                            f"(Data.Constr {index} [{', '.join(items)}])"))
            for j, (f, ft) in enumerate(fields):
                w = Terms(tr)
                w.n = first_var
                bad = w.wrong(ft)
                if bad is not None:
                    out.append((f"{c}_wrongKind_{plain(f)}", f"{c} with field `{plain(f)}` of the wrong kind",
                                w.binders, w.ctor(index, fields, {j: bad})))
    return out

def malformed_redeemer_checks(info):
    """Selected malformed cases with the original quantifiers and acceptance predicate."""
    binder = " (p : Params)" if info.has_params else ""
    params = " p" if info.has_params else ""
    declarations = []
    for handler in info.handlers:
        ctx = EVERY[handler.purpose]
        for suffix, text, binders, term in malformed(
                info.translator, handler.redeemer_kind, handler.redeemer_ctors, 0):
            quantifiers = " ".join(binders + [f"(t : {ctx})"])
            declarations += [
                f"/-- No {NOUN[handler.purpose]} is accepted within ledgerFuel with {text}. -/",
                f"theorem malformedRedeemer_{handler.purpose}_{suffix}{binder} :",
                f"    ∀ {quantifiers},",
                f"      ¬ accepts ledgerFuel{params} ({ctx}.ctx t {term}) := by blaster", ""]
    lines = [f"-- Generated by process_blueprint.py from {info.origin}. Do not edit; regenerate.",
             "import Blaster", "import Formal.Universal.Properties", f"import {info.prefix}.Types",
             "", "set_option Elab.async false", "", f"namespace {info.prefix}", "",
             "open PlutusCore.Data (Data)", "open PlutusCore.ByteString (ByteString)",
             "open CardanoLedgerApi.IsData.Class (IsData)",
             "open CardanoLedgerApi.V3 (Address Credential PubKeyHash StakingCredential TxOutRef)",
             "open Formal.Universal.Properties", "",
             "/-! UP-005: no success within ledgerFuel for the selected malformed redeemer cases.",
             "The full TxInfo and purpose fields are variables. The cases are not exhaustive.",
             "Fuel exhaustion satisfies these claims; it does not establish an explicit error.",
             "-/", ""]
    if not declarations:
        lines += ["-- No typed redeemer cases: no UP-005 goals generated.", ""]
    return lines + declarations + [f"end {info.prefix}"]



def require_return_datum_schema(tr, schema, visiting=()):
    """Refuse constraints or recursion that the existing decoder would not enforce."""
    annotations = {"title", "description", "$comment"}
    if "$ref" in schema:
        if set(schema) - annotations - {"$ref"}:
            raise ExtractError("returnDatum does not support constrained references")
        key, resolved = tr.resolve(schema)
        if key in visiting:
            raise ExtractError("returnDatum does not support recursive datum schemas")
        require_return_datum_schema(tr, resolved, visiting + (key,))
        if key in LEDGER_TYPES and tr.ledger_layout_matches(resolved, LEDGER_TYPES[key][1]):
            expected = {
                "Credential": {0: [("bytes",)], 1: [("bytes",)]},
                "StakingCredential": {0: [("ledger", "Credential")], 1: [("int",)] * 3},
                "Address": {0: [("ledger", "Credential"), ("option", ("ledger", "StakingCredential"))]},
                "TxOutRef": {0: [("bytes",), ("int",)]}
            }[LEDGER_TYPES[key][0]]
            for ctor in resolved["anyOf"]:
                actual = [tr.ty(field, key) for field in ctor.get("fields", [])]
                if actual != expected[ctor["index"]]:
                    raise ExtractError(f"returnDatum cannot use the ledger decoder for {key}")
        return
    if "anyOf" in schema:
        allowed, children = {"anyOf"}, schema["anyOf"]
        indices = [child.get("index") for child in children]
        if not children or len(indices) != len(set(indices)):
            raise ExtractError("returnDatum requires distinct constructor tags in a nonempty union")
    else:
        kind = schema.get("dataType")
        allowed = {"dataType"} if kind is not None else set()
        children = []
        if kind == "constructor":
            allowed |= {"index", "fields"}
            children = schema.get("fields", [])
        elif kind == "list":
            allowed.add("items")
            items = schema.get("items", {})
            if items == []:
                raise ExtractError("returnDatum does not support empty tuple schemas")
            children = items if isinstance(items, list) else [items]
        elif kind == "map":
            allowed |= {"keys", "values"}
            children = [schema.get("keys", {}), schema.get("values", {})]
    unsupported = set(schema) - annotations - allowed
    if unsupported:
        raise ExtractError(f"returnDatum does not support datum constraints: {', '.join(sorted(unsupported))}")
    for child in children:
        require_return_datum_schema(tr, child, visiting)


def return_datum_checks(bp, info):
    """UP-006 over every output of every model-valid accepted context, without shapes."""
    if bp.get("preamble", {}).get("plutusVersion") != "v3":
        raise ExtractError("returnDatum requires an explicit Plutus V3 blueprint")
    entries = find_entries(bp, info.head)
    if any(e.get("parameters") for e in entries):
        raise ExtractError("returnDatum requires an applied snapshot with no remaining blueprint parameters")
    if info.datum_type is None:
        raise ExtractError("returnDatum requires a declared spending datum schema")
    schema = next(e["datum"]["schema"] for e in entries if e["title"].endswith(".spend"))
    require_return_datum_schema(Translator(bp.get("definitions", {})), schema)
    code = compiled_code(entries)
    if not isinstance(code, str) or not re.fullmatch(r"(?:[0-9a-fA-F]{2})+", code):
        raise ExtractError("returnDatum requires nonempty compiledCode hex")
    digest = hashlib.blake2b(b"\x03" + bytes.fromhex(code), digest_size=28).digest()
    if any(not isinstance(e.get("hash"), str) or e["hash"].lower() != digest.hex() for e in entries):
        raise ExtractError("returnDatum: blueprint hash does not match the Plutus V3 compiledCode")
    octets = ", ".join(str(n) for n in digest)
    decoder = dec(info.datum_type, "datum", Fresh())
    return ["set_option Elab.async false", "",
            "open CardanoLedgerApi.V3 (ScriptContext validScriptContext)",
            "open Formal.Universal.Properties (ledgerFuel)",
            "open Formal.Universal.ReturnDatum (allReturnDatumsValid)", "",
            "/-- Script identity computed from compiledCode and checked against the blueprint. -/",
            "def returnDatumScriptHash : ByteString :=",
            f"  ⟨String.mk (([{octets}] : List Nat).map Char.ofNat)⟩", "",
            "/-- Schema-aware decoding; inline datum presence is checked separately by the helper. -/",
            "def returnDatumConforms (datum : Data) : Bool :=",
            f"  ({decoder} : Option SpendDatum).isSome", "",
            "/-- Every matching output of an accepted modeled transaction has a conforming inline datum.",
            "    Includes optional outputs and all positions; acceptance uses the existing CEK step bound. -/",
            "def returnDatumGoal : Prop :=",
            "  ∀ (ctx : ScriptContext), validScriptContext ctx = true →",
            "    accepts ledgerFuel ctx →",
            "    allReturnDatumsValid returnDatumScriptHash returnDatumConforms",
            "      ctx.scriptContextTxInfo.txInfoOutputs = true", "",
            "theorem returnDatum : returnDatumGoal := by blaster", "",
            f"end {info.prefix}"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("blueprint", nargs="?")
    ap.add_argument("validator", nargs="?", help="`module.validator` or an unambiguous `validator`")
    ap.add_argument("--out", default="Formal/Blueprint", help="folder for generated Lean files, under Formal/")
    ap.add_argument("--scripts", default="Scripts", help="directory for the .cbor file, as seen by Lean")
    output = ap.add_mutually_exclusive_group()
    output.add_argument("--cbor-only", action="store_true", help="copy compiledCode as hex and print its path")
    output.add_argument("--check", choices=["otherPurpose", "malformedRedeemer", "returnDatum"],
                        help="also write Checks.lean for this family")
    ap.add_argument("--translation", action="store_true", help="print the translation table and exit")
    a = ap.parse_args()
    if a.translation:
        print(TRANSLATION)
        return
    if not (a.blueprint and a.validator):
        ap.error("a blueprint and a validator are required")
    try:
        bp = json.loads(Path(a.blueprint).read_text())
        if a.cbor_only:
            entries = find_entries(bp, a.validator)
            path = Path(cbor_path_of(entries, a.scripts))
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(compiled_code(entries))
            print(path)
            return
        prefix = module_prefix(a.out)
        if a.check == "returnDatum":
            prefix += ".ReturnDatum"
        lines, info = generate(bp, a.validator, prefix, a.scripts, inline_script=a.check == "returnDatum")
        checks = (["import Blaster", "import Formal.Universal.ReturnDatum"] + lines
                  + return_datum_checks(bp, info)) if a.check == "returnDatum" else None
    except (ExtractError, KeyError, json.JSONDecodeError) as e:
        sys.exit(f"process_blueprint: {e}")
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if a.check == "returnDatum":
        target = out / "Checks.lean"
        with tempfile.TemporaryDirectory(prefix=".return-datum-", dir=out) as staging:
            temporary = Path(staging) / "Checks.lean"
            temporary.write_text("\n".join(checks) + "\n")
            temporary.replace(target)
        print(f"wrote {target}")
    else:
        target = out / "Types.lean"
        target.write_text("\n".join(lines + [f"end {info.prefix}"]) + "\n")
        print(f"wrote {target}")
        if a.check:
            target = out / "Checks.lean"
            checks = other_purpose_checks(info) if a.check == "otherPurpose" else malformed_redeemer_checks(info)
            target.write_text("\n".join(checks) + "\n")
            print(f"wrote {target}")
            if a.check == "otherPurpose" and {h.purpose for h in info.handlers} == set(PURPOSES):
                print("otherPurpose: no undeclared purposes; no checks apply")
            elif a.check == "malformedRedeemer" and not any(MALFORMED[h.redeemer_kind] for h in info.handlers):
                print("malformedRedeemer: no typed redeemer cases; no checks generated")
    for warning in info.warnings:
        print(f"warning: {warning}")


if __name__ == "__main__":
    main()

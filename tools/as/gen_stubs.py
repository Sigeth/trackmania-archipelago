#!/usr/bin/env python3
"""Generate an AngelScript stub surface for the Openplanet API.

Input : tools/as/api/OpenplanetCore.json   (script core API)
        tools/as/api/OpenplanetTurbo.json  (engine nod classes)
Output: tools/as/generated/openplanet.stub.as

The stub file is one AngelScript translation unit that *declares* every
Openplanet type, enum, funcdef, global function and global property the plugin
could reference, with generated (do-nothing) bodies. Compiling it together with
`src/**.as` in a standalone AngelScript engine turns `Reload plugin` compile
errors -- wrong method name, wrong argument type, undeclared identifier, missing
return -- into CI failures.

What is NOT emitted here (the C++ host registers real, working versions so the
unit tests can execute):  string, wstring, array, dictionary, dictionaryValue,
ref, the `Json` namespace, and the primitive types.

Run:  python tools/as/gen_stubs.py
CI `asrun --gen-check` re-runs this and fails if generated/ is stale.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
API = HERE / "api"
# $ASRUN_GEN (set by check.ps1) puts the generated stub outside the repo, so it
# is never picked up as plugin source when this tree is symlinked into the
# Openplanet plugins folder. Unset (CI) -> the in-tree tools/as/generated/.
GEN_DIR = Path(os.environ["ASRUN_GEN"]) if os.environ.get("ASRUN_GEN") else HERE / "generated"
OUT = GEN_DIR / "openplanet.stub.as"
SRC = HERE.parent.parent / "src"


def plugin_declared_names() -> set[str]:
    """Type names the plugin itself declares -- the safety net must not shadow them."""
    names: set[str] = set()
    pat = re.compile(r"^\s*(?:shared\s+|abstract\s+)*"
                     r"(?:class|enum|interface|namespace)\s+([A-Za-z_]\w*)", re.M)
    fpat = re.compile(r"\bfuncdef\s+[\w:@<>]+\s+([A-Za-z_]\w*)\s*\(")
    # top-level (non-indented) global functions -- Render/Update/Main/... callbacks
    gpat = re.compile(r"^[A-Za-z_][\w:@<>\[\] ]*?\s([A-Za-z_]\w*)\s*\(", re.M)
    for f in SRC.rglob("*.as"):
        t = f.read_text("utf-8", errors="replace")
        names.update(pat.findall(t))
        names.update(fpat.findall(t))
        names.update(gpat.findall(t))
    return names

# Types the C++ host registers for real -- never emit a script stub for these.
RUNTIME_TYPES = {
    "void", "bool", "int", "int8", "int16", "int32", "int64",
    "uint", "uint8", "uint16", "uint32", "uint64", "float", "double",
    "string", "array", "dictionary", "dictionaryValue",
    "dictionaryIter", "ref", "any",
}
# Namespaces the host owns completely (working C++ implementations).
RUNTIME_NS = {"Json", "Text"}

# Core "classes" that are really templates (their methods mention subtype T).
# Engine members that use them are already remapped to array<...>@.
SKIP_CORE_CLASSES = {
    "MwSArray", "MwFastArray", "MwFastBuffer", "MwFastBufferCat", "MwRefBuffer",
    "array", "grid",
}

# Global functions the host registers -- skip them here to avoid double definition.
RUNTIME_FUNCS = {
    "print", "warn", "error", "trace", "tostring", "startnew", "yield", "sleep",
    "assert", "throw", "getExceptionInfo",
}

# AngelScript reserved words -- never emit a member with one of these names.
AS_KEYWORDS = {
    "and", "auto", "bool", "break", "case", "cast", "class", "const", "continue",
    "default", "do", "double", "else", "enum", "false", "float", "for", "funcdef",
    "if", "import", "in", "inout", "int", "interface", "is", "mixin", "namespace",
    "not", "null", "or", "out", "return", "switch", "true", "typedef", "uint",
    "void", "while", "xor", "shared", "abstract", "external", "private", "protected",
    "this", "super", "explicit", "property", "get", "set", "from", "function",
    "try", "catch",
}

PRIMITIVE_RET = {
    "bool": "false",
    "int": "0", "int8": "0", "int16": "0", "int32": "0", "int64": "0",
    "uint": "0", "uint8": "0", "uint16": "0", "uint32": "0", "uint64": "0",
    "float": "0", "double": "0",
    "string": '""', "wstring": '""',
}

# ---------------------------------------------------------------------------
# collectors

emitted_classes: set[str] = set()          # bare names, for safety-net / body logic
_emitted_core_qual: set[str] = set()       # "<ns>::<name>", for core-class dedup
emitted_enums: set[str] = set()
emitted_funcdefs: set[str] = set()
referenced_types: set[str] = set()


def note_type(decl: str) -> None:
    """Record every bare type name mentioned in a declaration fragment."""
    for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", decl or ""):
        referenced_types.add(tok)


def strip_to_typename(t: str) -> str:
    t = t.strip()
    t = re.sub(r"\bconst\b", "", t)
    t = t.replace("&in", "").replace("&out", "").replace("&inout", "").replace("&", "")
    t = t.replace("@", "").strip()
    m = re.match(r"^array<(.+)>$", t)
    if m:
        return strip_to_typename(m.group(1))
    return t.split("::")[0].strip()


# ---------------------------------------------------------------------------
# engine type mapping

_ARRAYish = ("MwFastBuffer", "MwFastArray", "MwSArray", "MwRefBuffer", "MwArray", "Array")


def map_engine_arglist(a: str) -> str:
    """Sanitise an engine method arg string ('CMwNod@ Nod, MwFastBuffer<wstring>& X')
    into something the script compiler accepts."""
    if not a:
        return ""
    a = a.replace("&", "")  # engine out-params: model as plain value/handle
    a = re.sub(r"\b[A-Za-z_]\w*(?:::[A-Za-z_]\w*)+", "int", a)  # scoped enum types -> int
    # collapse any Name<...> (MwFastBuffer, MwArray, ...) down to array<...>@
    for _ in range(4):  # bounded; handles the rare nested container
        new = re.sub(r"\b(?!array\b)[A-Za-z_]\w*<([^<>]+)>", r"array<\1>@", a)
        if new == a:
            break
        a = new
    a = re.sub(r"\bwstring\b", "string", a)
    _drop = {"DEPRECATED", "const", "in", "out", "inout"}
    parts, used = [], set()
    for i, chunk in enumerate(_split_args(a)):
        toks = [t for t in chunk.split() if t not in _drop]
        if not toks:
            continue
        typ = toks[0]
        name = toks[1] if len(toks) > 1 and toks[1] not in AS_KEYWORDS else ""
        if not name or name in used:
            name = f"a{i}"
        used.add(name)
        parts.append(f"{typ} {name}")
    return ", ".join(parts)


def _split_args(a: str) -> list[str]:
    out, depth, cur = [], 0, ""
    for ch in a:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def map_engine_type(t) -> str:
    """OpenplanetTurbo.json member type string -> an AngelScript type."""
    if not isinstance(t, str) or t == "":
        return "int"
    t = t.strip()
    # ClassName::ENested  -> we model every nested engine enum as int
    if "::" in t:
        return "int"
    if t in ("UnnamedEnum", "UnknownType"):
        return "int" if t == "UnnamedEnum" else "CMwNod@"
    m = re.match(r"^[A-Za-z_]\w*<(.+)>$", t)
    if m:  # every engine container (MwFastBuffer, MwFastBufferCat, MwArray, ...) -> array
        inner = map_engine_type(m.group(1))
        prims = {"bool", "int", "uint", "float", "double", "string",
                 "int8", "int16", "int64", "uint8", "uint16", "uint64",
                 "vec2", "vec3", "vec4", "int2", "int3", "nat2", "nat3"}
        if not inner.endswith("@") and inner not in prims:
            inner += "@"       # object subtypes as handles -> no default-factory needed
        return f"array<{inner}>@"
    if t in _ARRAYish or t.startswith("Mw") and t.endswith(("Buffer", "Array", "BufferCat")):
        return "array<CMwNod@>@"
    if t == "wstring":
        return "string"
    return t  # X, X@, primitives, vec3, MwId, ... (safety net covers unknowns)


# ---------------------------------------------------------------------------
# body synthesis

def default_body(ret: str) -> str:
    r = (ret or "void").strip()
    r = re.sub(r"\bconst\b", "", r).strip()
    if r in ("", "void"):
        return " {}"
    if r.endswith("&"):
        r = r[:-1].strip()  # can't return a reference from script; fall through
    if r.endswith("@"):
        return " { return null; }"
    if r in PRIMITIVE_RET:
        return f" {{ return {PRIMITIVE_RET[r]}; }}"
    if r.split("::")[-1] in emitted_enums:
        return f" {{ return {r}(0); }}"
    # value type: default-construct and return it
    return f" {{ {r} __r; return __r; }}"


# ---------------------------------------------------------------------------
# emit: enums

def emit_enum(name: str, values: list[tuple[str, int]], ns: str | None, out: list[str]) -> None:
    if name in RUNTIME_TYPES or name in emitted_enums:
        return
    if ns and ns in RUNTIME_NS:
        return
    emitted_enums.add(name)
    body = ", ".join(f"{k} = {v}" for k, v in values) if values else "_None = 0"
    line = f"enum {name} {{ {body} }}"
    out.append(f"namespace {ns} {{ {line} }}" if ns else line)


def core_enums(core: dict, out: list[str]) -> None:
    out.append("// ---- core enums ----")
    for e in core["enums"]:
        vals = [(k, d["v"]) for k, d in e.get("values", {}).items()]
        emit_enum(e["name"], vals, e.get("ns"), out)


# ---------------------------------------------------------------------------
# emit: funcdefs

def core_funcdefs(core: dict, out: list[str]) -> None:
    out.append("\n// ---- funcdefs ----")
    for fd in core["funcdefs"]:
        args = fd.get("args", [])
        adecls = [a.get("typedecl", "") for a in args]
        if any(re.fullmatch(r"T", a) for a in adecls):
            continue  # templated helper funcdef -- comes with the array add-on
        ret = fd.get("returntypedecl", "void")
        name = fd["name"]
        if name in emitted_funcdefs or name in ("CoroutineFunc",):
            continue  # CoroutineFunc is an application funcdef (registered in C++)
        emitted_funcdefs.add(name)
        note_type(ret)
        for a in adecls:
            note_type(a)
        out.append(f"funcdef {ret} {name}({', '.join(adecls)});")


# ---------------------------------------------------------------------------
# emit: global + namespaced functions

def _split_ret_name(decl_head: str) -> tuple[str, str]:
    """'CGameCtnApp@ GetApp' -> ('CGameCtnApp@', 'GetApp')."""
    parts = decl_head.rsplit(None, 1)
    if len(parts) == 1:
        return "void", parts[0]
    return parts[0], parts[1]


def core_functions(core: dict, out: list[str]) -> None:
    out.append("\n// ---- global / namespaced functions ----")
    by_ns: dict[str, list[str]] = {}
    for f in core["functions"]:
        ns = f.get("ns") or ""
        if ns.split("::")[0] in RUNTIME_NS:
            continue
        decl = f.get("decl", "")
        if "(" not in decl:
            continue
        head, _, rest = decl.partition("(")
        ret, name = _split_ret_name(head.strip())
        if name in ("opAssign",) or name in RUNTIME_FUNCS or name in AS_KEYWORDS:
            continue
        if "?" in rest:
            continue  # variadic-type param -> C++ registration only
        note_type(ret)
        note_type(rest)
        body = default_body(ret)
        by_ns.setdefault(ns, []).append(f"    {decl}{body}")
    for ns, lines in sorted(by_ns.items()):
        uniq = list(dict.fromkeys(lines))
        if ns:
            out.append(f"namespace {ns} {{")
            out.extend(uniq)
            out.append("}")
        else:
            out.extend(l.strip() for l in uniq)


def core_props(core: dict, out: list[str]) -> None:
    out.append("\n// ---- global properties ----")
    by_ns: dict[str, list[str]] = {}
    for p in core.get("props", []):
        ns = p.get("ns") or ""
        t = p.get("typedecl", "int")
        name = p["name"]
        note_type(t)
        base = re.sub(r"\bconst\b", "", t).replace("@", "").strip()
        init = "null" if t.strip().endswith("@") else PRIMITIVE_RET.get(base, None)
        if init is None:
            decl = f"    {t} {name};"
        else:
            decl = f"    {t.replace('const', '').strip()} {name} = {init};"
        by_ns.setdefault(ns, []).append(decl)
    for ns, lines in sorted(by_ns.items()):
        if ns:
            out.append(f"namespace {ns} {{")
            out.extend(lines)
            out.append("}")
        else:
            out.extend(l.strip() for l in lines)


# ---------------------------------------------------------------------------
# emit: core classes

def core_classes(core: dict, out: list[str]) -> None:
    out.append("\n// ---- core classes ----")
    for c in core["classes"]:
        name = c["name"]
        ns = c.get("ns")
        if name in RUNTIME_TYPES or name in SKIP_CORE_CLASSES:
            continue
        if ns and ns in RUNTIME_NS:
            continue
        qual = f"{ns or ''}::{name}"
        if qual in _emitted_core_qual:
            continue
        _emitted_core_qual.add(qual)
        emitted_classes.add(name)
        members: list[str] = [f"    {name}() {{}}"]   # explicit default ctor (value-subtype arrays need one)
        # constructors (from behaviours) -- needed for e.g. IO::File(string, FileMode)
        for b in c.get("behaviors", []):
            bd = b.get("func", {}).get("decl", "")
            if not bd or bd.startswith("~") or bd.startswith("$"):
                continue
            if "(" not in bd or ")" not in bd:
                continue
            inside = bd[bd.index("(") + 1: bd.rindex(")")].strip()
            if inside == "" or "?" in inside:
                continue  # implicit default ctor, or ?-param (C++-only, not script)
            note_type(bd)
            members.append(f"    {name}({inside}) {{}}")
        for p in c.get("props", []):
            if p["name"] in AS_KEYWORDS:
                continue
            t = p.get("typedecl") or p.get("typename") or "int"
            note_type(t)
            members.append(f"    {t} {p['name']};")
        seen_sig: set[str] = set()
        for m in c.get("methods", []):
            decl = m["decl"].strip()
            decl = re.sub(r"\bconst\s*$", "", decl).strip()
            if decl in seen_sig or "?" in decl:
                continue  # ?-param methods are C++-registration only
            seen_sig.add(decl)
            head = decl.split("(")[0]
            ret, _ = _split_ret_name(head.strip())
            note_type(decl)
            # a script class can't return a reference
            decl = decl.replace("&opIndex", " opIndex")
            if re.search(r"^\s*[\w:<>@]+&\s", decl) or "& opIndex" in decl:
                continue
            members.append(f"    {decl}{default_body(ret)}")
        block = "\n".join(members)
        cls = f"class {name} {{\n{block}\n}}" if block else f"class {name} {{}}"
        out.append(f"namespace {ns} {{\n{cls}\n}}" if ns else cls)


# ---------------------------------------------------------------------------
# emit: engine classes (topologically sorted by single-inheritance)

def engine_classes(turbo: dict, out: list[str]) -> None:
    out.append("\n// ---- engine nod classes (flattened to global namespace) ----")
    flat: dict[str, dict] = {}
    for members in turbo["ns"].values():
        for cn, cd in members.items():
            flat.setdefault(cn, cd)

    order: list[str] = []
    done: set[str] = set()

    def visit(cn: str) -> None:
        if cn in done or cn not in flat:
            return
        parent = flat[cn].get("p")
        if parent and parent in flat and parent not in done:
            visit(parent)
        done.add(cn)
        order.append(cn)

    for cn in flat:
        visit(cn)

    # member names contributed by each class, so descendants don't redefine them
    own_members: dict[str, set[str]] = {}

    def inherited_names(cn: str) -> set[str]:
        acc: set[str] = set()
        p = flat.get(cn, {}).get("p")
        while p and p in flat:
            acc |= own_members.get(p, set())
            p = flat[p].get("p")
        return acc

    for cn in order:
        cd = flat[cn]
        if cn in RUNTIME_TYPES or cn in emitted_classes:
            continue
        emitted_classes.add(cn)
        parent = cd.get("p")
        base = f" : {parent}" if parent and parent in flat else ""
        if parent and parent in flat:
            referenced_types.add(parent)
        members: list[str] = []
        seen: set[str] = set(inherited_names(cn))
        mine: set[str] = set()
        for m in cd.get("m", []):
            n = m["n"]
            if n in AS_KEYWORDS:
                continue
            t = m.get("t")
            if isinstance(t, int):  # method
                ret = m.get("r") if isinstance(m.get("r"), str) else "void"
                args = m.get("a") if isinstance(m.get("a"), str) else ""
                sig = f"{n}({args})"
                if sig in seen or n in seen:
                    continue
                seen.add(sig)
                mine.add(n)
                ret = map_engine_type(ret) if ret != "void" else "void"
                args = map_engine_arglist(args)
                note_type(ret)
                note_type(args)
                members.append(f"    {ret} {n}({args}){default_body(ret)}")
            else:  # property
                if n in seen:
                    continue
                seen.add(n)
                mine.add(n)
                at = map_engine_type(t)
                note_type(at)
                members.append(f"    {at} {n};")
        own_members[cn] = mine
        block = "\n".join(members)
        out.append(f"class {cn}{base} {{\n{block}\n}}" if block else f"class {cn}{base} {{}}")


# ---------------------------------------------------------------------------
# safety net: forward-declare anything referenced but never defined

def safety_net(out: list[str]) -> None:
    out.append("\n// ---- forward stubs for unresolved referenced types ----")
    known = (
        emitted_classes | emitted_enums | emitted_funcdefs | RUNTIME_TYPES | AS_KEYWORDS
        | {"T", "return", "null", "true", "false", "this",
           # registered by the C++ host, must not be script-declared:
           "CoroutineFunc", "Value", "Type", "DEPRECATED"}
    )
    known |= plugin_declared_names()
    missing = sorted(n for n in referenced_types if n not in known and re.match(r"^[A-Z]", n))
    for n in missing:
        out.append(f"class {n} {{}}")
    out.append(f"// {len(missing)} forward stub(s)")


# ---------------------------------------------------------------------------

def main() -> int:
    core = json.loads((API / "OpenplanetCore.json").read_text("utf-8"))
    turbo = json.loads((API / "OpenplanetTurbo.json").read_text("utf-8"))

    out: list[str] = [
        "// GENERATED by tools/as/gen_stubs.py -- do not edit.",
        f"// Openplanet: {core.get('op', '?')}",
        "// Declares the Openplanet API surface so src/**.as can be type-checked",
        "// outside the game. Bodies are inert. string/array/dictionary/Json and",
        "// the primitives come from the C++ host, not from here.",
        "",
    ]
    core_enums(core, out)
    core_funcdefs(core, out)
    core_classes(core, out)
    engine_classes(turbo, out)
    core_functions(core, out)
    core_props(core, out)
    safety_net(out)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out) + "\n", "utf-8", newline="\n")
    try:
        shown = OUT.relative_to(HERE.parent.parent)
    except ValueError:
        shown = OUT  # written outside the repo (ASRUN_GEN)
    print(f"wrote {shown} "
          f"({len(emitted_classes)} classes, {len(emitted_enums)} enums, "
          f"{OUT.stat().st_size // 1024} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

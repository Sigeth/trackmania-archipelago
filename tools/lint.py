#!/usr/bin/env python3
"""Static checks for the Openplanet plugin + apworld.

This is NOT a compiler -- `tools/as/` is (a real AngelScript type-check of
`src/**.as`; run `pwsh tools/as/check.ps1` or the `angelscript` CI job). This
script is the fast first pass: text hygiene, manifest shape, version agreement,
and the documented API-trap warnings. What it catches:

  errors (exit 1):
    * unbalanced () [] {} in a .as file  -- a guaranteed load failure
    * non-UTF-8 bytes, CRLF line endings, literal tabs, trailing whitespace
    * info.toml missing required keys / bad version
    * info.toml / archipelago.json / apworld __init__.py version disagreement

  warnings (exit 0, printed):
    * API traps documented in plugin/CLAUDE.md ('Draw::' does not exist on the
      Turbo build; 'Net::WebSocket' must stay inside src/net/Transport.as)

Run from the repo root: python tools/lint.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        tomllib = None  # type: ignore

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


# --- AngelScript bracket balance -------------------------------------------------

_PAIRS = {")": "(", "]": "[", "}": "{"}
_OPEN = set(_PAIRS.values())


def check_brackets(path: Path, text: str) -> None:
    stack: list[tuple[str, int]] = []
    i, line, n = 0, 1, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "\n":
            line += 1
        elif c == "/" and nxt == "/":
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        elif c == "/" and nxt == "*":
            j = text.find("*/", i + 2)
            if j == -1:
                err(f"{path}: unterminated /* block comment (line {line})")
                return
            line += text.count("\n", i, j)
            i = j + 2
            continue
        elif c == '"' and text[i : i + 3] == '"""':
            j = text.find('"""', i + 3)
            if j == -1:
                err(f'{path}: unterminated """ string (line {line})')
                return
            line += text.count("\n", i, j)
            i = j + 3
            continue
        elif c in ('"', "'"):
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                err(f"{path}: unterminated {c} string literal (line {line})")
                return
            i = j + 1
            continue
        elif c in _OPEN:
            stack.append((c, line))
        elif c in _PAIRS:
            if not stack or stack[-1][0] != _PAIRS[c]:
                near = stack[-1] if stack else ("<none>", 0)
                err(f"{path}:{line}: unmatched '{c}' (open was {near[0]!r} at line {near[1]})")
                return
            stack.pop()
        i += 1
    if stack:
        c, ln = stack[-1]
        err(f"{path}: {len(stack)} unclosed bracket(s); last is {c!r} opened at line {ln}")


# --- per-file text hygiene -----------------------------------------------------

def check_text(path: Path, raw: bytes) -> str | None:
    rel = path.relative_to(ROOT).as_posix()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        err(f"{rel}: not valid UTF-8 ({e})")
        return None
    if "\r" in text:
        err(f"{rel}: CRLF line endings (.gitattributes says eol=lf)")
    for k, ln in enumerate(text.splitlines(), 1):
        if "\t" in ln:
            err(f"{rel}:{k}: literal tab (style: 4-space indent)")
            break
    for k, ln in enumerate(text.splitlines(), 1):
        if ln != ln.rstrip():
            err(f"{rel}:{k}: trailing whitespace")
            break
    if text and not text.endswith("\n"):
        err(f"{rel}: no final newline")
    return text


# --- API traps (warn only) ---------------------------------------------------

def check_traps(path: Path, text: str) -> None:
    rel = path.relative_to(ROOT).as_posix()
    for k, ln in enumerate(text.splitlines(), 1):
        code = ln.split("//", 1)[0]
        if "Draw::" in code:
            warn(f"{rel}:{k}: 'Draw::' — no such namespace on the Turbo build (use nvg:: / UI::*DrawList)")
        if "Net::WebSocket" in code and rel != "src/net/Transport.as":
            warn(f"{rel}:{k}: 'Net::WebSocket' outside src/net/Transport.as — the transport must stay encapsulated")


# --- manifests --------------------------------------------------------------

def check_info_toml() -> str | None:
    p = ROOT / "info.toml"
    if not p.is_file():
        err("info.toml: missing")
        return None
    if tomllib is None:  # pragma: no cover - only on <3.11 without tomli
        m = re.search(r'version\s*=\s*"([^"]+)"', p.read_text("utf-8"))
        print("warning: no TOML parser available, info.toml structure not checked")
        return m.group(1) if m else None
    data = tomllib.loads(p.read_text("utf-8"))
    meta = data.get("meta", {})
    for key in ("name", "author", "version", "category"):
        if not meta.get(key):
            err(f"info.toml: [meta].{key} is missing or empty")
    ver = meta.get("version", "")
    if ver and not re.fullmatch(r"\d+\.\d+\.\d+", ver):
        err(f"info.toml: [meta].version {ver!r} is not X.Y.Z")
    return ver or None


def check_versions_agree(toml_ver: str | None) -> None:
    aj = ROOT / "apworld/trackmania_turbo/archipelago.json"
    ini = ROOT / "apworld/trackmania_turbo/__init__.py"
    if not aj.is_file() or not ini.is_file():
        err("apworld/trackmania_turbo: archipelago.json or __init__.py missing")
        return
    json_ver = json.loads(aj.read_text("utf-8")).get("world_version")
    m = re.search(r'__version__\s*=\s*"([^"]+)"', ini.read_text("utf-8"))
    init_ver = m.group(1) if m else None
    if len({toml_ver, json_ver, init_ver}) != 1:
        err(
            "version mismatch — info.toml="
            f"{toml_ver} archipelago.json={json_ver} __init__.py={init_ver}"
        )


# --- main ------------------------------------------------------------------

def main() -> int:
    toml_ver = check_info_toml()
    check_versions_agree(toml_ver)

    as_files = sorted((ROOT / "src").rglob("*.as"))
    if not as_files:
        err("src/: no .as files found")
    for path in as_files:
        raw = path.read_bytes()
        text = check_text(path, raw)
        if text is None:
            continue
        check_brackets(path.relative_to(ROOT).as_posix(), text)
        check_traps(path, text)

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(
        f"\n{len(as_files)} .as file(s) checked — "
        f"{len(errors)} error(s), {len(warnings)} warning(s)"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

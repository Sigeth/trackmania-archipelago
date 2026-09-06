#!/usr/bin/env python3
"""Write a version string into the three places that must agree.

Called by semantic-release (@semantic-release/exec prepareCmd) with the computed
next version, e.g.  python tools/bump_version.py 0.1.0

Targets:
  * info.toml                                   [meta].version
  * apworld/trackmania_turbo/archipelago.json   world_version
  * apworld/trackmania_turbo/__init__.py        __version__

tools/lint.py enforces that these stay identical.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sub_once(path: Path, pattern: str, repl: str) -> None:
    text = path.read_text(encoding="utf-8")
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit(f"bump_version: pattern {pattern!r} matched {n}x in {path} (expected 1)")
    path.write_text(new, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        return print("usage: bump_version.py X.Y.Z") or 2
    v = sys.argv[1]

    sub_once(ROOT / "info.toml",
             r'(?m)^(version\s*=\s*")[^"]*(")', rf'\g<1>{v}\g<2>')
    sub_once(ROOT / "apworld/trackmania_turbo/archipelago.json",
             r'("world_version"\s*:\s*")[^"]*(")', rf'\g<1>{v}\g<2>')
    sub_once(ROOT / "apworld/trackmania_turbo/__init__.py",
             r'(__version__\s*=\s*")[^"]*(")', rf'\g<1>{v}\g<2>')

    print(f"bump_version: set {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

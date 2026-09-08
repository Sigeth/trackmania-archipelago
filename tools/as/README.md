# `tools/as` — headless AngelScript compile + unit tests

Openplanet only compiles the plugin's AngelScript when you `Reload plugin`
in-game, and there is no standalone Openplanet compiler. This directory builds
one anyway: a small C++ host (`asrun`) links the real **AngelScript** library,
registers a generated stub of the entire Openplanet API plus working
`string` / `array` / `dictionary` / `Json`, and compiles `src/**.as` as a single
module — a genuine parser + type-checker. It also runs AngelScript unit tests for
the pure modules.

```
asrun --compile src                 # compile gate: non-zero exit on any error
asrun --test    src tools/as/tests  # + run every global  void Test_*()
```

## Layout

| Path | What |
|------|------|
| `api/OpenplanetCore.json`, `api/OpenplanetTurbo.json` | Snapshots of Openplanet's own API dumps (`%USERPROFILE%/OpenplanetTurbo/…`). The **only** committed inputs. `api/op-version.txt` records which build. |
| `gen_stubs.py` | `api/*.json` → `generated/openplanet.stub.as` — every namespace, enum, funcdef, class (inert bodies). Gitignored output; regenerated on every build. |
| `overrides.as` | Hand-written fixups loaded after the generated stub. |
| `host/` | `main.cpp` (driver), `op_string.cpp` / `op_bindings.cpp` (string/array/dict/Text/log with Openplanet's spelling), `json_value.cpp` (a real minimal `Json::`). |
| `tests/` | `_assert.as` + `test_*.as`. A test is a global `void Test_*()`; a failed `Assert` throws and the runner reports `FAIL`. |
| `CMakeLists.txt` | Fetches AngelScript (`codecat/angelscript-mirror`, pinned) via FetchContent and builds `asrun`. |
| `check.ps1` | Local Windows run — finds MSVC, grabs a portable CMake, regenerates + builds + runs. No admin install. |

## Running it

**Local (Windows):** `pwsh tools/as/check.ps1` (add `-NoTest` for the gate only,
`-Clean` to wipe the build tree). Needs Visual Studio's MSVC toolset; CMake and
AngelScript are downloaded to `%LOCALAPPDATA%\op-asrun-cache`.

**CI:** the `angelscript` job in `.github/workflows/ci.yml` (cmake + gcc, both
preinstalled on the runner).

**Manual:** `python tools/as/gen_stubs.py` then
`cmake -S tools/as -B tools/as/build && cmake --build tools/as/build` then run
`asrun` as above.

## What it catches — and what it doesn't

**Catches:** syntax errors, unknown identifiers, misspelled / renamed engine
members, wrong argument count or type, bad return types, missing returns, most
operator misuse — i.e. the errors that would fail `Reload plugin`.

**Does not catch:** the generated API classes are AngelScript *script classes*,
not the engine's registered interface, so value-vs-reference semantics, exact
const-correctness, and property-accessor edge cases are approximate. `Transport`,
`GameState` and the UI code are compile-checked only — their engine / socket
dependencies are inert stubs, so they are never executed. This is a fast
pre-flight, **not** a substitute for reloading in-game.

## Refreshing the API after an Openplanet update

Copy the two dumps and record the version, then rebuild:

```
cp "$USERPROFILE/OpenplanetTurbo/OpenplanetCore.json"  tools/as/api/
cp "$USERPROFILE/OpenplanetTurbo/OpenplanetTurbo.json" tools/as/api/
# update tools/as/api/op-version.txt to the new "op" string
pwsh tools/as/check.ps1
```

If new API shapes trip `gen_stubs.py`, extend the generator (its skip-lists and
`map_engine_type` cover the known odd cases) or add a fixup to `overrides.as`.

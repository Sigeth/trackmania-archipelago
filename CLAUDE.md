# CLAUDE.md — Archipelago plugin for Trackmania Turbo

Guidance for Claude Code / contributors working in this repo.

## What this is

An Openplanet (AngelScript) plugin bridging **Trackmania Turbo** and the
**Archipelago** multiworld randomizer. Finishing a run on an official campaign
track becomes an Archipelago *location check*; *items* received from the
multiworld unlock campaign tracks, enforced client-side because Turbo exposes no
unlock API.

The server side is the `trackmania_turbo` **.apworld**, whose source lives in this
repo under `apworld/trackmania_turbo/` (shipped and versioned together with the
plugin — see "Packaging" below). The strings in "Naming contract" below are what
the two halves agree on.

## Build / run / test

There is no compiler or test runner. **Build = reload:**
`Openplanet > Developer > Reload plugin`. Compile errors and `print`/`warn`/
`error` output go to the Openplanet log window and
`%USERPROFILE%\OpenplanetTurbo\Openplanet.log` (which flushes lazily — reload to
force it). Turn on `Settings > Archipelago > Debug > Verbose protocol logging`
(`S_Trace`) for per-frame tracing.

Dev install — symlink this folder into the plugins dir:

```
cmd /c mklink /D "%USERPROFILE%\OpenplanetTurbo\Plugins\Archipelago" "%CD%"
```

Manual testing: run a local `ArchipelagoServer` (or `MultiServer.py`) hosting a
`Trackmania Turbo` world on `localhost:38281`, connect the plugin (`ws://`, TLS
off), and exercise flows in-game. A `ArchipelagoTextClient` on the same slot is a
useful independent observer.

Style: 4-space indent, `PascalCase` methods, `m_` private fields, `S_` settings,
`g_` globals. No linter — match the surrounding file.

## Packaging / releases

- **One version, two artifacts.** `info.toml` `meta.version`,
  `apworld/trackmania_turbo/archipelago.json` `world_version`, and that world's
  `__init__.py` `__version__` are kept identical — `tools/lint.py` (run by CI)
  fails the build if they drift.
- **semantic-release** (`.github/workflows/release.yml` + `.releaserc.json`) runs
  on every push to `main`: analyses the conventional-commit log and, when a
  release is due, runs `tools/bump_version.py` (the three version spots),
  regenerates `CHANGELOG.md`, runs `tools/package.sh`, commits the bumped files
  back to `main` (`chore(release): … [skip ci]`), tags `vX.Y.Z`, and publishes a
  GitHub Release with `dist/Archipelago.op` (`info.toml` + `src/`) and
  `dist/trackmania_turbo.apworld` (the `apworld/trackmania_turbo/` folder, minus
  `test/` / `__pycache__`).
- Pre-1.0: `feat:` → minor, `fix:` → patch, `feat!:` / `BREAKING CHANGE:` →
  `1.0.0`. So use `!` deliberately — it is the trigger for the first major.
- A `v0.0.0` tag (at commit `d38a069`) is the baseline, so the first release
  semantic-release cuts is `0.1.0`.
- No release PRs, so it does **not** need the "allow Actions to create pull
  requests" repo setting that blocked release-please — only "Read and write
  permissions" under Settings > Actions > General. If `main` becomes a protected
  branch that blocks the Actions bot's push, drop `@semantic-release/git` from
  `.releaserc.json` (tag + Release still publish; only the bump-back commit is
  lost).
- `ci.yml` runs on every push/PR (and weekly, Mon 06:00 UTC):
  - `plugin` job — `tools/lint.py` then trial-zips the `.op`.
  - `angelscript` job — `gen_stubs.py`, build `tools/as` (CMake fetches
    AngelScript), then `asrun --compile src` + `asrun --test src tools/as/tests`.
  - `apworld` job — resolves `apworld/.ap-version` (`stable` → the latest
    non-prerelease Archipelago release, i.e. what archipelago.gg hosts on; or an
    explicit `X.Y.Z` pin), checks that core out, drops the world in, runs
    `pytest worlds/trackmania_turbo/test test/general -k Trackmania` + a
    `Generate.py` smoke. The weekly run is what catches a new stable core
    release breaking the world with no commit here.
- **AngelScript compile + unit tests — `tools/as/`.** There is no standalone
  Openplanet compiler, so `tools/as/` builds one: a C++ host (`asrun`) links the
  real AngelScript library, registers a generated stub of the whole Openplanet
  API (from the `api/*.json` dumps) plus working `string`/`array`/`dictionary`/
  `Json`, and compiles `src/**.as` as one module — a genuine type-check.
  `asrun --compile src` is the gate; `asrun --test src tools/as/tests` runs the
  `Test_*` unit tests (TrackTable, Protocol, DataPackage, Notify). CI job `angelscript`;
  local `pwsh tools/as/check.ps1`. It catches renamed members / wrong signatures
  / undeclared names / bad returns, but the stubs are script classes not the
  registered interface — `Transport`/`GameState`/UI are compile-only, and a real
  compile still only happens on `Reload plugin`. See `tools/as/README.md`.
- `tools/lint.py` still runs first for text hygiene (UTF-8 / LF / tab / trailing
  whitespace), `info.toml` shape, the 3-way version check, and the documented
  API-trap warnings (`Draw::`, `Net::WebSocket` outside `Transport.as`).
- Openplanet-registry upload of the `.op` stays manual.

## Architecture

Data flows in two directions, meeting at `ApClient`:

```
game thread (Update)                     client coroutine (Main loop)
  GameState.Update()                        ApClient.Update()
    reads CGameCtnApp nod                     transport.Pump()  -> inbound frames
    emits FinishEvent on a race finish        Packet::Parse + Dispatch
        │                                        ├─ Connected     -> LocationManager.SeedFromServer
        ▼                                        └─ ReceivedItems -> ItemManager.OnReceivedItems
  LocationManager.OnFinish  ──────────────►         │
    TrackTable: map number -> label                 ▼
    DataPackage: name -> id                   ItemManager: client-enforced unlock set
    ApClient.SendLocationChecks ──► transport
```

Key seams: **all engine access is confined to `src/game/GameState.as`**, **all
socket access to `src/net/Transport.as`**. Everything else is pure data transform
and reasons without the game or a server.

### Threading

`Update(float dt)` is called by Openplanet on the **game thread** — the only safe
place to touch `GetApp()` / engine nods. `Main()` runs a coroutine doing network
+ JSON only. Cross-thread hand-off is one nullable field: `GameState.pendingFinish`,
produced and consumed in `Update` (same thread). Don't call into `GameState` from
the coroutine; don't touch engine nods from `ApClient` / managers.

### Networking

The Turbo Openplanet build (1.29.x) has **no `Net::WebSocket`**. `Transport.as`
is a minimal RFC 6455 client over `Net::Socket` (which supports TLS via
`Connect(host, port, secure)`): HTTP upgrade handshake, masked text frames out,
unmasked + fragmented + ping/pong in. Nothing outside this file knows WebSocket
exists.

The receive buffer is `array<uint8>`, **not `string`** — `Net::Socket.ReadRaw`
and AngelScript string concat truncate at the first `0x00`, and WebSocket frame
length headers contain zero bytes (any payload length that is a multiple of 256).
Read via `Socket.ReadBuffer` → `MemoryBuffer`; only turn a NUL-free JSON payload
into a `string`.

### Openplanet Turbo API traps

- **`dictionary` has no `Get(string, int&out)`** — only `int64&out`, `double&out`,
  generic `?&out`. The generic path does not round-trip a 32-bit `int` (returns
  stale values). Always use `int64` with dictionary number values; prefer
  `.Set(k, v)` over `d[k] = v`.
- **`CGameCtnChallengeInfo.Medal` / `.BestTime` are blank for campaign maps**
  (`EMedal=0`, `BestTime=0xFFFFFFFF`). No saved solo progress there. `GameState`
  reads the finish from `CTrackManiaPlayer.RaceState` (`app.CurrentPlayground.
  GameTerminals[0].ControlledPlayer`) → on the edge into `Finished`, the time from
  `CurRace.Time` (poll a few ticks — not ready the instant the state flips),
  medal from `challenge.TMObjective_{Bronze,Silver,Gold,Author}Time`.
- Campaign map identity: `challenge.MapName` is `"001".."200"`,
  `challenge.AuthorLogin == "Nadeo"` — no UID table. Same method the Ultimate
  Medals plugin uses (`Phlarx/tm-ultimate-medals`).

Grep `%USERPROFILE%\OpenplanetTurbo\OpenplanetCore.json` (script API) and
`Openplanet.h` (engine nods) before assuming a class or method exists — much of
the online Openplanet docs describe the newer TM2020 build.

- **No `Draw::` namespace.** Screen drawing is `nvg::` (only from a global
  `void Render()` — drawn even with the Openplanet overlay closed) or
  `UI::Get*DrawList()`.
- **The campaign overlay** (`src/ui/CampaignOverlay.as`, the plugin's only
  `Render()`): no menu API, so it walks the Nadeo ManiaLink tree via
  `cast<CTrackManiaMenus>(app.MenuManager).MenuCustom_CurrentManiaApp`.
  - **Series-overview grid** (200 tiles): shown when `UILayers[12].IsVisible`
    *and* layer 11's `Frame_AllBrowseTrack` is hidden. Tile geometry from layer
    11: find frame `ControlId == "FrameAll_Buttons"`, its `Frame_Instance*`
    children are the 200 tiles (row-major); map number from the
    `MouseInput_Track_<R>:<C>` child
    (`n = (R/2)*40 + (C/5)*10 + (R%2)*5 + (C%5) + 1`), position from
    `AbsolutePosition_V3` (ML; tile `48.21 × 45.0`, `y` up). Layer 12's own tiles
    use opaque ids; layer 11's positions coincide with layer 12's render.
  - **Per-series track picker** (10 thumbnails): shown when layer 11's
    `Frame_AllBrowseTrack.Visible`. Those tiles aren't reachable; read the series
    from `FrameAll_Buttons.Controls[3]` (`Label_Diff0`) text and the environment
    from which column `Frame_Selector` sits in, then draw at 10 fixed slots.
  - layer 11's own `IsVisible` / frame-visible flags are IDENTICAL between the
    series grid and the main menu — only `UILayers[12].IsVisible` /
    `Frame_AllBrowseTrack.Visible` disambiguate the three states.
- **ML → screen has no exposed transform** on this build (menu mouse coords
  `CGameManiaApp.MouseX/Y` are a *different* space — do not use them). Both grids
  are mapped into a screen rect given as window fractions (`S_GridL/T/R/B` for the
  200-grid, `S_TpL/T/R/B` for the picker), calibrated once by eye with the Debug
  "Overlay alignment" sliders + box-preview, and persisted. Re-tune per
  resolution/aspect.
- **Writing Nadeo ManiaLink control fields does NOT stick.** Every tile has a
  hidden native `Quad_Locked` (`locked-2x2.dds`); setting `.Visible = true` on it
  executes but the menu's own script re-hides it the same frame, so it never
  renders. No MLHook for Turbo. Overlays must be *drawn* (`nvg`), not injected.

### Archipelago protocol notes

- Frames are JSON **arrays** of command objects (`Packet::WrapArray` / `Parse`).
- Handshake: `RoomInfo` → (`GetDataPackage` if checksum changed) → `Connect`
  (`items_handling = 7`, `slot_data = true`) → `Connected` | `ConnectionRefused`.
- On `Connected` the client sends `Sync` (replay all items so reconnects restore
  unlocks) then `StatusUpdate(Playing)`.
- `ReceivedItems.index == 0` = full replay — reset local item state first. A
  non-zero `index != m_nextIndex` = a gap → send `Sync`.
- Location sends are optimistic; `RoomUpdate.checked_locations` is the confirmation.
- `PrintJSON` is the room feed (chat, item routing, hints, joins). `ApClient`
  colourises the `data` parts into `chatLog` (`FormatPart` resolves `player_id`
  via the slot→alias map, `item_id` / `location_id` via the data package) and the
  chat panel sends `Say` for plain lines *and* server commands (`!hint`, `!help`).

### Files

| File | Responsibility |
|------|----------------|
| `src/Main.as` | Lifecycle, globals (`g_client`, `g_gameState`), per-frame wiring |
| `src/Settings.as` | `[Setting]` vars, `Medal` enum, `ServerUrl()` |
| `src/Log.as` | Logging facade; `Log::Trace` gated on `S_Trace` |
| `src/net/Transport.as` | Hand-rolled WebSocket: connect / `Pump()` / `Send()` / close |
| `src/ap/Protocol.as` | AP constants, packet builders, frame parser (`Packet::`) |
| `src/ap/DataPackage.as` | Server id ⇄ name maps, disk-cached by checksum |
| `src/ap/ApClient.as` | Session state machine (`Ap::Phase`), handshake, dispatch |
| `src/game/GameState.as` | Reads the Turbo nods; emits `FinishEvent` on a race finish; bounces the player out of locked tracks |
| `src/game/TrackTable.as` | Campaign map number (1–200) ⇄ `"<Tier> <Env> NN"` label |
| `src/game/LocationManager.as` | finish → location id; dedupe; batched send; per-track checked-medal mask |
| `src/game/ItemManager.as` | consumes `ReceivedItems`; counts `<grade> Medal` items; client-enforced 20-block unlock gate |
| `src/ui/Window.as` | Status window + `RenderMenu()` entry + chat panel (log view + input; sends `Say`) |
| `src/ui/Notify.as` | `UI::ShowNotification` toasts, raised from `ApClient.OnPrintJson` for `ItemSend`/`ItemCheat` routes touching this slot — server's own sentence with our slot as "you"/"You" (`S_Notifications`) |
| `src/ui/CampaignOverlay.as` | `Render()` — nvg lock / medal-pip markers on the series grid *and* the per-series track picker |

## Naming contract with the `.apworld`

If you change one of these, change it on both sides.

- Game name: `"Trackmania Turbo"` (`AP_GAME_NAME` in `Protocol.as`).
- Track label: `"<Tier> <Environment> NN"`, e.g. `"White Canyon 01"`.
  Tier ∈ {White, Green, Blue, Red, Black} (difficulty order).
  Environment ∈ {Canyon, Valley, Lagoon, Stadium}. NN = 01..10. 200 tracks total.
  Campaign map number 1..200 → these difficulty-major, then environment, then NN
  (`TrackLabel` in `TrackTable.as`).
- Location: `"<Track Label> - <Medal>"`, e.g. `"White Canyon 01 - Gold"`.
  Medal ∈ {Bronze, Silver, Gold, Author}. A seed only defines the tiers at/above
  the `medals_required` floor (default Gold → Gold + Author).
- Milestone locations: `"<Tier> <Env> Complete"` (×20, all 10 tracks of a block
  finished) and `"<Tier> Complete"` (×5, all 40 of a tier). A bare finish
  (no medal) is **not** a check — the plugin tracks it locally
  (`LocationManager.m_finishedTracks`, persisted `seed-<name>-finished.json`) to
  drive the milestones and the `campaign_finish` goal.
- Medal item: `"Bronze Medal"` / `"Silver Medal"` / `"Gold Medal"` — the
  randomised progression. Block `i` (10 tracks in campaign order,
  `i = tier*4 + env`, 0..19) opens once the received count of the block-grade
  medal (`Bronze i<8`, `Silver i<16`, `Gold i≥16`) reaches `block_thresholds[i]`
  (`= 10*i`, block 0 always open). Once a block is open, finishing a track sends
  whatever medal the player earned — no licence gate.
- `slot_data`: `unlock_style` (always `"vanilla"`), `goal` (always
  `"campaign_finish"`) — still sent, plugin warns on anything else;
  `block_thresholds` (20 ints); `medals_required` (`bronze|silver|gold|author`,
  the per-track check floor).

## Open items

- **Track-lock enforcement UX — done, verified in-game (1920×1080).**
  `CampaignOverlay.as` marks locked tracks with a padlock on both the series grid
  and the track picker (unlocked tracks get Bronze/Silver/Gold/Author pips for
  checked medals); `GameState.LockedNow()` calls `BackToMainMenu()` when the
  player loads a locked campaign map (`S_BlockLockedTracks`) — confirmed it lands
  cleanly and writes no time. Only remaining: the grid-rect / picker-slot
  calibration is per-resolution (re-tune with the Debug sliders on other setups).
- **Goal condition — done.** One goal: `campaign_finish` fires at
  `LocationManager.FinishedCountAll() >= 200`. `ItemManager.CheckGoal()` warns
  if `slot_data.goal` is anything else.
- **Unlock mode — one model (retail-style block gate), pending in-game test.**
  `ItemManager` counts `<grade> Medal` items and opens the 20 blocks from
  `slot_data.block_thresholds`; `LocationManager` milestones + `m_finishedTracks`
  persistence; `GameState` emits `FinishEvent` on a **no-medal finish** too
  (`FinishEvent.medal` may be `Medal(0)`). VERIFY in-game: a sub-Bronze run still
  reaches `RaceState == Finished` with a readable time; blocks unlock as medal
  items land; milestone checks fire; reconnect rebuilds the finished set.
- **Medal-detection breadth.** Verified for one track; spot-check the finish
  signal and `CurRace.Time` on a few more, and whether solo always passes through
  `RaceState == Finished` (fallback: `CGamePlaygroundScript.Solo_NewRecordSequenceInProgress`).
- **`wss://` path.** Only `ws://` (local) is exercised so far; test TLS +
  fragmented inbound frames against `archipelago.gg`.
- Debug traces in `GameState` / `LocationManager` / `ItemManager` / `Transport`
  are gated on `S_Trace` and can be trimmed once bring-up settles.

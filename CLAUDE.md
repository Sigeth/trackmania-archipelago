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

Dev install — deploy **only the plugin payload** (`info.toml` + `src/`), never
the whole repo. Openplanet compiles every `.as` anywhere under a plugin folder
into one module, so a whole-repo symlink drags in `tools/as/` (the generated API
stub, the unit tests, `overrides.as`, and the AngelScript SDK sources CMake
fetches into `tools/as/build/_deps/`) and the load fails with `#include` /
`#pragma` / duplicate-section errors.

```
set "AP=%USERPROFILE%\OpenplanetTurbo\Plugins\Archipelago"
mkdir "%AP%"
mklink /J "%AP%\src" "%CD%\src"
mklink /J "%AP%\assets" "%CD%\assets"
mklink /H "%AP%\info.toml" "%CD%\info.toml"
```

`assets/` holds runtime files loaded by plugin-relative path
(`Audio::LoadSample("assets/voice-medal-gold.wav")`) — no `.as` in there, so the junction is
safe. It ships in the `.op` too.

`/J` (junction) and `/H` (hard link) need no elevation, unlike `mklink /D`. The
hard link breaks if `info.toml` is rewritten out of place (a `git` checkout that
changes it, e.g. a release bump) — re-run the last line if the version in-game
looks stale. This layout is exactly what `dist/Archipelago.op` ships.

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
  GitHub Release with `dist/Archipelago.op` (`info.toml` + `src/` + `assets/`) and
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

**No `permessage-deflate` (known issue).** The AP server prints "your client
does not support compressed websocket connections" on every connect. `Transport`
sends no `Sec-WebSocket-Extensions` header and does not handle the RSV1
(compressed) frame bit, so the server never compresses and the connection is
fine — the warning is purely forward-compat. It is **not fixable on this build**:
the Turbo Openplanet API has no DEFLATE/inflate/zlib primitive at all (checked
`OpenplanetCore.json` and `Crypto::`), and no other Openplanet AngelScript plugin
has implemented WS compression (`chipsTM/tm-websockets` is likewise a hand-rolled
RFC 6455 with none). Closing it would mean porting a pure-script inflater
(~300–500 lines). Deferred until a future AP server actually rejects uncompressed
clients. See workspace `CLAUDE.md` open question 1.

**Known issue — idle disconnect after ~10 minutes (2026-09-12, not yet
root-caused).** Reported live: the local `MultiServer.py` test server closes
the connection after roughly 10 minutes idle even though `Transport.as` is
provably replying to every server ping (`<< ping (server), replying pong` in
the trace log) and `SendFrame` refreshes `m_lastSendMs` on every send,
including that pong. So our RFC 6455 ping/pong handling looks correct; the
timeout is happening somewhere that doesn't treat control frames as
"activity" — maybe `MultiServer`'s own idle-connection reaper (keyed off real
message traffic), maybe a NAT/router/firewall TCP idle timeout unrelated to
the WS layer, maybe specific to local dev and not `archipelago.gg`. See
workspace `CLAUDE.md` open question 1 for the full note and what to check
first (`TRANSPORT_KEEPALIVE_INTERVAL_MS`, `Transport.as:28`, actually firing
every 30s).

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
  - **The menu pans `FrameAll_Buttons` between screens (bug found 2026-09-12).**
    Its ML-space position drifts depending on which series/environment was last
    browsed in the picker — confirmed in-game: after visiting any picker other
    than White Canyon, the series grid's tiles come back offset by roughly one
    series width, and the picker's own environment detection (via
    `Frame_Selector`'s x) always read back as Canyon regardless of the real
    selection. Fix: the grid's ML bounding box is no longer a probe-measured
    constant — `Overlay::GridBounds()` recomputes it every frame from the
    currently-visible tiles' own `AbsolutePosition_V3` (self-calibrating,
    immune to the pan), and `PickerState()` reads `Frame_Selector`'s x
    *relative to* `FrameAll_Buttons`'s own (also panned) position instead of a
    fixed origin. VERIFY in-game across all 4 environments and after
    navigating grid → picker → grid a few times (only Canyon was ever
    confirmed before this fix).
- **ML → screen has no exposed transform** on this build (menu mouse coords
  `CGameManiaApp.MouseX/Y` are a *different* space — do not use them). Both grids
  are mapped into a screen rect given as window fractions (`S_GridL/T/R/B` for the
  200-grid, `S_TpL/T/R/B` for the picker), calibrated once by eye with the Debug
  "Overlay alignment" sliders + box-preview, and persisted. Re-tune per
  resolution/aspect — the ML-space side of the mapping is now self-calibrating
  (see above), only the screen-fraction anchor still needs manual tuning.
- **Writing Nadeo ManiaLink control fields does NOT stick.** Every tile has a
  hidden native `Quad_Locked` (`locked-2x2.dds`); setting `.Visible = true` on it
  executes but the menu's own script re-hides it the same frame, so it never
  renders. No MLHook for Turbo. Overlays must be *drawn* (`nvg` /
  `UI::Get*DrawList`), not injected. The game's own medal/record ceremony also
  can't be triggered from a plugin (`Solo_SetNewRecord`,
  `PlayUiSound(EUISound::Record)` etc. are all ManiaScript-only) — hence
  `MedalSplash.as` draws its own.
- **Driving the campaign menu's medal display from Archipelago is not feasible**
  on this build (deep dive 2026-09-09; see the user memory
  `ap-only-campaign-medals`). The menu loads all 200 records once in a racy async
  burst into one shared buffer, never re-queries (not even after finishing that
  map), and no script proc fires on the save. `RecordGuard.as` /
  `S_FreshProfile` were removed.

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
| `src/game/LocationManager.as` | finish → location id; dedupe; batched send; per-track checked-medal mask; reports what a finish armed (for the splash) |
| `src/game/ItemManager.as` | consumes `ReceivedItems`; counts `"Progressive Medal"` items; client-enforced 20-block unlock gate; queues trap item names for `TrapManager` |
| `src/game/TrapManager.as` | Applies trap items on the game thread: blind (nvg overlay), giant/tiny car (`CTrackManiaRace.ScaleCarValue`, unverified), respawn (`BackToMainMenu()`) |
| `src/ui/Window.as` | Status window + `RenderMenu()` entry + chat panel (log view + input; sends `Say`) |
| `src/ui/Notify.as` | `UI::ShowNotification` toasts, raised from `ApClient.OnPrintJson` for `ItemSend`/`ItemCheat` routes touching this slot — server's own sentence with our slot as "you"/"You" (`S_Notifications`) |
| `src/Main.as` `Render()` | The plugin's single `Render()` — `RenderCampaignOverlay()` then `MedalSplash::Render()` |
| `src/ui/CampaignOverlay.as` | `RenderCampaignOverlay()` — nvg lock / medal-pip markers on the series grid *and* the per-series track picker |
| `src/game/VfsSound.as` | Auto-fetches the game's own announcer voice lines at runtime from the player's `Documents\TrackmaniaTurbo\` asset cache (`Fids::` **User** drive), keyword-matched per medal tier |
| `src/ui/MedalSplash.as` | Centred foreground-draw-list medal banner on every campaign finish + a medal voice line (via `VfsSound`, or a manual `assets/voice-medal-*.wav` override) on a Gold/Author finish that armed a check |

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
- Medal item: `"Progressive Medal"` — one currency for the whole campaign, no
  grade distinction. Block `i` (10 tracks in campaign order, `i = tier*4 + env`,
  0..19) opens once the received count reaches `block_thresholds[i]` (`= 10*i`,
  block 0 always open). Once a block is open, finishing a track sends whatever
  medal the player earned — no licence gate. A per-grade `"Bronze/Silver/Gold
  Medal"` economy was tried and found mathematically unsolvable solo (see the
  apworld's `__init__.py` module docstring) — `unlock_style: real_medals` is
  reserved for a future, carefully-scaled reintroduction; selecting it raises
  `OptionError` at generation time, and the plugin only implements
  `"progressive"`.
- `slot_data`: `unlock_style` (`"progressive"`, `"real_medals"` reserved), `goal`
  (always `"campaign_finish"`) — still sent, plugin warns on anything else;
  `block_thresholds` (20 ints); `medals_required` (`bronze|silver|gold|author`,
  the per-track check floor).
- Trap items (`TRAP_NAMES` in the apworld's `__init__.py`, `TRAP_*` constants
  in `TrackTable.as`): `"Blind Trap"`, `"Giant Car Trap"`, `"Tiny Car Trap"`,
  `"Respawn Trap"`. `ItemClassification.trap`; the apworld's `trap_chance`
  option (0..100%, default 0) rolls from `ACTIVE_TRAP_NAMES` — currently just
  `"Blind Trap"`, the only one confirmed working — in place of `"Nitro Boost"`
  filler. No slot_data involved — `TrapManager.as` applies the effect entirely
  client-side on receipt. See workspace `CLAUDE.md` open question 7 for full
  in-game test results and why Giant/Tiny Car and Respawn are dormant.

## Open items

- **Track-lock enforcement UX — mostly done, one pan bug just fixed, pending
  in-game re-verification.** `CampaignOverlay.as` marks locked tracks with a
  padlock on both the series grid and the track picker (unlocked tracks get
  Bronze/Silver/Gold/Author pips for checked medals); `GameState.LockedNow()`
  calls `BackToMainMenu()` when the player loads a locked campaign map
  (`S_BlockLockedTracks`) — confirmed it lands cleanly and writes no time.
  2026-09-12: found the menu pans `FrameAll_Buttons` depending on which
  series/environment was last browsed, which broke both the series grid
  (tiles landed offset after visiting a picker) and the picker's own
  environment detection (always read back as Canyon) — see the API-traps
  section above for the fix (self-calibrating grid bounds + a pan-relative
  `Frame_Selector` read). VERIFY in-game across all 4 environments and after
  bouncing between grid and picker a few times. Grid-rect / picker-slot
  *screen*-fraction calibration is still per-resolution (re-tune with the
  Debug sliders on other setups).
- **Goal condition — done.** One goal: `campaign_finish` fires at
  `LocationManager.FinishedCountAll() >= 200`. `ItemManager.CheckGoal()` warns
  if `slot_data.goal` is anything else.
- **Unlock mode — one model (single-currency progressive block gate), pending
  in-game test.** `ItemManager` counts `"Progressive Medal"` items and opens
  the 20 blocks from `slot_data.block_thresholds`; `LocationManager` milestones
  + `m_finishedTracks` persistence; `GameState` emits `FinishEvent` on a
  **no-medal finish** too (`FinishEvent.medal` may be `Medal(0)`). VERIFY
  in-game: a sub-Bronze run still reaches `RaceState == Finished` with a
  readable time; blocks unlock as medal items land; milestone checks fire;
  reconnect rebuilds the finished set.
- **Medal-detection breadth.** Verified for one track; spot-check the finish
  signal and `CurRace.Time` on a few more, and whether solo always passes through
  `RaceState == Finished` (fallback: `CGamePlaygroundScript.Solo_NewRecordSequenceInProgress`).
- **`wss://` path.** Only `ws://` (local) is exercised so far; test TLS +
  fragmented inbound frames against `archipelago.gg`.
- **Medal splash — needs an in-game look; sound auto-fetch CONFIRMED WORKING
  end-to-end (2026-09-13, Gold voice line audibly heard on a real trigger).**
  `MedalSplash.as` shows a centred banner on every campaign finish (track +
  earned medal, plus "Checked: …" / milestone lines when connected).
  `src/game/VfsSound.as` pulls the medal voice lines from Openplanet's
  `Fids::` API at runtime, so a player doesn't need to hand-extract
  `assets/voice-medal-*.wav` with an external NadeoPak tool. Getting there
  took a real investigation (full trail in `VfsSound.as`'s header comment) —
  three layered wrong guesses, not one:
  1. `Fids::GetGameFolder("")` (the **Game** drive) is the literal on-disk
     install dir (`GameData\`, `Packs\`, ...), not a merged pak view —
     `GameData\Media\Sounds` resolves but is completely empty.
  2. The **User** drive (`Fids::GetUserFolder("")`, →
     `Documents\TrackmaniaTurbo\`) does list 90+ real-looking entries under
     `Media\Sounds\TMConsole\Voices\` (`voice-carhit-*`, `checkpoint`,
     `voice-medal-*`, ...), of the 5 Fids drives only User had it — but
     those entries are virtual reference records (`.FullFileName ==
     "<virtual>"`, `.ByteSize` 38–539 bytes even for `voice-carhit-*`, which
     definitely plays on every collision), not the audio payload.
  3. `Fids::Extract(fid)` reports success against them, but
     `Fids::GetFullPath(fid)` is USELESS here — confirmed it returns just
     the containing folder, no filename, no drive letter. Guessing the real
     extracted-to location every plausible way (the scan's own folder path,
     `IO::FromAppFolder`/`FromDataFolder` combined with the fid's own state)
     all failed `IO::FileExists` too.
  **The actual answer**, found by searching GitHub for other Openplanet
  plugins' real `Fids::Extract` usage (`AurisTFG/tm-fid-loader`'s
  `FidWrapper.as`): extraction lands under Openplanet's own **Data folder**,
  in an `Extract\` subfolder mirroring the drive-relative path with no drive
  name in the string — `IO::FromDataFolder("Extract\" + <path> +
  fid.FileName)`. That's what `VfsSound::ExtractedPath()` builds now,
  confirmed with `IO::FileExists` before wiring it into the real pipeline.
  `VfsSound::EnsureScanned()` walks `SCAN_PATHS`
  (`User\Media\Sounds\TMConsole\Voices`) one path segment at a time via
  `FindChild()` matching child-folder names against
  `Fids::UpdateTree()`-populated `.Trees` (`GetGameFolder`/`GetUserFolder`
  don't resolve a compound path for an unwalked subtree either), keeping
  each leaf's `CSystemFidFile@` handle directly from `.Leaves` and building
  its `ExtractedPath()` alongside it as the walk recurses. Keyword-matches
  `bronze`/`silver`/`gold`/`author` per tier, falling back to a shared
  `victory`/`record`/`podium`/`reward` cue for any tier with no dedicated
  file. A manual `assets/voice-medal-{bronze,silver,gold,author}.wav`
  override (`MedalSplash::SAMPLE_FILE`) still wins when present.
  `Window.as`'s "Medal splash" section has a "Scan game files for medal
  sounds" button + `VfsSound::DebugSummary()` readout. The one-off "Probe
  ..." functions used during the 2026-09-13 investigation (VFS drives/roots,
  file header hex dump, extract location) were removed once the real
  mechanism was confirmed and wired in -- re-derive similar probes from this
  file's own trail (above) if a future Openplanet update ever breaks this
  again. **VERIFY in-game:** only Gold has been audibly confirmed so
  far — spot-check Bronze/Silver/Author too (keyword matching is a
  heuristic, and `voice-medal-{bronze,silver,author}.wav` were assumed to
  exist by naming convention, not individually confirmed), and check
  behaviour on a fresh profile that hasn't played enough for the User-drive
  cache to be populated yet (the manual override is the fallback for that
  case). All sound goes through `MedalSplash::PlayTierSound()`, which MUST
  run on the game thread — `VfsSound`'s Fids::/Audio:: calls inherit that
  same rule. One trigger: a **Gold or Author finish that armed a check** →
  Gold /
  Author line (Author wins when the run cleared both; `SplashInfo.medal` is
  already the single best tier). Bronze/Silver finishes are silent. (There
  used to be a second trigger — a received Bronze/Silver/Gold medal *item*
  playing that tier's line — but the apworld now sends a single ungraded
  `"Progressive Medal"` item, so there's no tier to announce on receipt;
  dropped until `unlock_style: real_medals` ships.) The game's own jingle
  can't be triggered directly (`PlayUiSound` / `PlaySoundLibrary` are
  ManiaScript-only). VERIFY placement/legibility at
  1920×1080 and on the in-map results screen; "Test medal splash" + per-tier
  "Audition voice lines" buttons are in the window's "Medal splash" section.
- Debug traces in `GameState` / `LocationManager` / `ItemManager` / `Transport`
  are gated on `S_Trace` and can be trimmed once bring-up settles.
- **Traps — implemented 2026-09-12; only Blind Trap confirmed working.**
  `TrapManager.as` applies four trap items; `ItemManager` queues their names
  from `OnReceivedItems` (network thread) and `Main.as` drains the queue once
  per `Update()` so the effects run on the game thread. Tested live against a
  local server + `!getitem` cheat while the user played.
  **Blind Trap** (nvg overlay, `S_BlindDurationSec` default 2s — was briefly
  8s, shortened per user feedback) — **confirmed working.** This is the only
  trap `ACTIVE_TRAP_NAMES` (in the apworld's `__init__.py`) selects; the other
  three stay in `TRAP_NAMES` / the id map but are never handed out.
  **Giant Car Trap / Tiny Car Trap** (`CTrackManiaRace.ScaleCarValue` via
  `app.CurrentPlayground.Interface` cast to `CTrackManiaRaceInterface` →
  `.Race`) — **confirmed NOT working**, correcting an earlier premature
  "confirmed" note here: the write/restore is clean in the log (no warning,
  correct value both ways) at the exact moment the user reported the car
  never visibly resized. A clean log trace only proves the code ran, not that
  the effect was visible — don't mark a trap VERIFIED without the user's eyes
  on it. Car-scale defaults were bumped 2.2/0.45 → 4.0/0.15 before this was
  caught (user: first pass wasn't dramatic enough) — those settings are now
  dormant pending a fix.
  **Lead tried via turbo.openplanet.dev and FALSIFIED in-game (2026-09-12).**
  That site showed `CTrackManiaRaceRules::EnableScaleCar` and both
  `CTrackManiaPlayer`/`CTmRaceRulesPlayer::TinyCar` as plain writable bools,
  so `TrapManager.StartCarScale()` briefly forced `EnableScaleCar` on before
  writing `ScaleCarValue`. That broke the real in-game compile: `The property
  has no set accessor`. Ground truth is the local dump Openplanet actually
  compiles against — `%USERPROFILE%\OpenplanetTurbo\OpenplanetTurbo.json`,
  grep for `"n":"EnableScaleCar"` / `"n":"TinyCar"` — which marks all three
  `"c":1` (read-only); the docs site doesn't expose that flag at all. None
  can be forced from script. Reverted: `CurrentRaceRules()` now only reads
  `EnableScaleCar` for diagnostic `Log::Trace`, never writes it. **Takeaway:
  turbo.openplanet.dev tells you a member exists and its shape, not whether
  Openplanet lets scripts write it — always cross-check `OpenplanetTurbo.json`'s
  `"c"` flag before coding against a property found there.** (Also caught
  `BonusCarScale`/`BonusCarScaleAccel` as `"c":1` despite showing unflagged on
  the site.) `ScaleCarValue` itself remains confirmed writable (no `"c"`
  flag, range `[0.1, 10]`) and still has no visible in-game effect on its
  own — a second, JSON-confirmed lead was then tried: `ScaleDuration` (uint)
  / `ScaleSpeedSec` (float) sit next to it on `CTrackManiaRace`, both
  genuinely writable, on the hypothesis that the mesh-scale interpolation
  only runs while a transition window is open (`ScaleDuration > 0`) and
  every prior attempt left it at its untouched default. `StartCarScale()`
  set both before `ScaleCarValue` and restored all three on expiry —
  confirmed via trace log the values round-tripped exactly as designed.
  **User confirmed live: still no visible resize for either trap. This lead
  is closed too.** `CMotionTrackMobilScale.ScaleValue` is also genuinely
  writable per the dump but is a confirmed dead end — nothing in the whole
  API returns/holds an instance of it, and the one plausible path
  (`CGameMobil.SceneMobil.MotionSolid`, typed `CMotion@`) is a structurally
  unrelated class hierarchy from `CMotionTrack`, so casting it only ever
  yields null. **Every writable, reachable scale-adjacent field found on
  `CTrackManiaRace`/`CTrackManiaRaceRules` has now been tried or ruled out.**
  **FOV warp diagnostic, same day — decisive negative result.** A debug-only
  button (`TrapManager::StartFovWarpDiagnostic()`, Window "Traps" section)
  multiplies the live `CTrackManiaRace.FovY` by 2.5x via the same accessor
  chain, to test whether the chain drives *any* visible effect at all (not
  just scale). Trace confirmed a huge swing (`FovY 65 -> 162.5`) applied and
  restored cleanly, fired twice. **User confirmed live both times: nothing
  visibly changed.** A swing that large would be unmissable if it reached
  the renderer — so `app.CurrentPlayground.Interface -> CTrackManiaRaceInterface
  -> .Race` very likely never reaches the object actually driving the
  rendered frame in solo campaign play. This was never scale-specific.
  Untested guess: `CTrackManiaRace` is a base class inherited by
  `CTrackManiaRaceNew`/`CTrackManiaRace1P`/`CTrackManiaRaceNet`; solo may run
  through a subclass with its own separate render path. **Don't trust this
  accessor chain for a future visual effect without first sanity-checking it
  reflects live state** (e.g. does `LapCount` actually change?). See the
  header comment in `TrapManager.as` for the full trail.
  Also note: `tools/as/gen_stubs.py` used to ignore the `"c"` flag when
  generating the AngelScript type-check stub, so `tools/as/check.ps1` passed
  this write clean — the compile error was only caught by an actual in-game
  plugin reload. **Fixed 2026-09-12:** `engine_classes()` now emits a
  `"c":1` property as a `get_`-only accessor (no field, so no setter), so
  `rules.EnableScaleCar = true;` now fails `check.ps1` too. One carve-out:
  `vec2`/`vec3`/`vec4`/`int2`/`int3`/`nat2`/`nat3`-typed properties are
  exempted (`FRAGILE_VALUE_TYPES`) because those core classes' copy
  constructor is an inert stub body, which would make a `get_` accessor
  silently return a zeroed value instead of failing to compile — see
  `tools/as/README.md`.
  **Respawn Trap** (`BackToMainMenu()`) — user feedback: "respawn is not what
  I wanted" (abandoning the run doesn't read as a respawn), then later folded
  into "mark everything else not working." Marked not-working as a trap.
  Candidates for next time: `CTrackManiaMenus.DialogQuitRace_OnRestartMap()`
  for a real in-place restart (untested — a menu dialog callback, may not
  behave standalone), drop the trap, or rename it (e.g. "DNF Trap") if the
  abandon-to-menu effect is ever wanted under an honest name.
  "Traps" debug buttons (fire the real effect immediately, broken ones
  labelled as such) are in the window. `trap_chance` defaults to 0 in the
  apworld, so no seed grows traps without the player opting in.
  **GitHub search closes this investigation for good (2026-09-14).** Searched
  for any real Openplanet plugin implementing a working car-resize trap.
  Zero hits. The only real-world code touching `EnableScaleCar`/car-scale is
  **ManiaScript mode scripts** (server-side `.Script.txt` files that define a
  game mode, e.g. `Plambt/TM-SMScripts`'s `KEKLRounds.Script.txt` /
  `Rounds-Chaos.Script.txt`, `BigBang1112/nadeo-envimix`'s
  `EnvimixTimeAttack.Script.txt`) — an entirely different, server-
  authoritative scripting environment with no path from an Openplanet client
  plugin. Those scripts only set the flag; the actual scale-application logic
  lives in Nadeo's own built-in base mode scripts (shipped with the game, not
  in any repo) and is driven by that mode's own bonus-event system. The one
  real Openplanet plugin found touching `EnableScaleCar` at all
  (`kalleruud/tm-webhooks-plugin`'s `TurboGameAdapter.as`) only reads it,
  never writes it. Conclusion: this isn't just "couldn't make it work" — the
  mechanism doesn't exist in any form reachable from an Openplanet plugin at
  all. See `TrapManager.as`'s header comment for the full citation trail.

# Archipelago — Trackmania Turbo

An [Openplanet](https://openplanet.dev) plugin that connects **Trackmania Turbo**
to the [Archipelago](https://archipelago.gg) multiworld randomizer.

Finishing a run on an official campaign track sends **location checks** to the
Archipelago server; **items** received from the multiworld unlock campaign tracks
(the plugin enforces the lock, since Turbo has no unlock API of its own).

> Status: early but working. A full round trip is verified end to end — connect,
> data package, finish a track in-game, location check sent, item routed back.
> Track-lock enforcement UX and the fuller item/goal set are still to come.

## Requirements

- Trackmania Turbo with the **Turbo build of Openplanet** installed
- An Archipelago server hosting a `Trackmania Turbo` world (the matching
  `.apworld`)

## Install (development)

Symlink or copy this folder into the Openplanet plugins directory, then
`Openplanet > Developer > Reload plugin`:

```
cmd /c mklink /D "%USERPROFILE%\OpenplanetTurbo\Plugins\Archipelago" "%CD%"
```

## Configure

Open the **Archipelago** window from the Openplanet menu: set the server host,
port, TLS toggle (off for a local server, on for `archipelago.gg`), your slot
name and optional password, then click **Connect**. The same fields also live
under `Openplanet > Settings > Archipelago`. Turn on
`Settings > Archipelago > Debug > Verbose protocol logging` to see every frame on
the wire.

## Packaging

Releases are automated with
[semantic-release](https://github.com/semantic-release/semantic-release). Every
conventional-commit push to `main` is analysed; when a release is due it bumps
the version, updates `CHANGELOG.md`, tags `vX.Y.Z`, and publishes a GitHub
Release with two assets:

- `Archipelago.op` — the Openplanet plugin (`info.toml` + `src/` zipped).
- `trackmania_turbo.apworld` — the matching Archipelago world (from `apworld/`).

Both carry the same version. It stays in `0.x` for `feat:` / `fix:`; the first
`feat!:` / `BREAKING CHANGE:` commit bumps it to `1.0.0`.

Publishing the `.op` to [openplanet.dev](https://openplanet.dev) is still a manual
upload — download it from the Release and upload it on the site.

To build both artifacts by hand: `bash tools/package.sh` → `dist/`.

## The `apworld/` folder

`apworld/trackmania_turbo/` is the source of truth for the Archipelago world (the
server half). It ships in this repo so the two halves version together and share
one home for the [naming contract](#naming-contract-with-the-apworld). CI runs its
tests on every push (and weekly) against the Archipelago core named by
`apworld/.ap-version` — `stable` by default, meaning the latest release, the one
archipelago.gg hosts games on. It is never included in `Archipelago.op`.

## Naming contract with the `.apworld`

These strings must match on both sides:

- Game name: `Trackmania Turbo`
- Location: `<Track Label> - <Medal>`, e.g. `White Canyon 01 - Gold`.
  Track label is `<Tier> <Environment> NN` — Tier ∈ {White, Green, Blue, Red,
  Black}, Environment ∈ {Canyon, Valley, Lagoon, Stadium}, NN = 01..10 (200
  tracks). Medal ∈ {Bronze, Silver, Gold, Author}.
- Progressive-unlock item: `Progressive <Tier>` (unlocks that tier's 40 tracks in
  campaign order).
- Individual-unlock item: `Unlock: <Track Label>`.

## Layout

- `info.toml` — plugin manifest (must stay at the repo root).
- `src/` — all AngelScript, compiled by Openplanet on load.
  - `net/Transport.as` — the only networking code: a hand-rolled RFC 6455
    WebSocket over `Net::Socket` (the Turbo Openplanet build has no
    `Net::WebSocket`).
  - `ap/` — Archipelago protocol, data package, session state machine.
  - `game/` — `GameState` (engine reads), `TrackTable` (map number → label),
    `LocationManager`, `ItemManager`.
  - `ui/Window.as` — status window.
- `apworld/` — the Archipelago world (Python), shipped and released alongside the
  plugin; never part of `Archipelago.op`.
- `tools/` — `lint.py` (static checks for the `.as` sources; no compiler exists
  outside Openplanet), `bump_version.py`, `package.sh`. All run by CI.
- `.github/workflows/` — `ci.yml` (lint + apworld tests + package check on every
  push and weekly), `release.yml` (semantic-release: tag + Release + assets).

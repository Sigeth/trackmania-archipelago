# Plugin assets

Runtime files the plugin loads by plugin-relative path
(`Audio::LoadSample("assets/…")`, `nvg::LoadTexture("assets/…")`).

## Medal ceremony sounds — auto-fetched at runtime, nothing to extract

`src/ui/MedalSplash.as` plays a medal voice line on a Gold-or-Author **finish**
that armed a check (`S_MedalSound`; Author wins when the run also cleared
Gold). A Bronze/Silver finish is silent.

The sound is Nadeo's own announcer audio. `src/game/VfsSound.as` reads it at
runtime from `Documents\TrackmaniaTurbo\Media\Sounds\TMConsole\Voices\` — a
per-player asset cache Nadeo's engine populates from the title pack as it's
used during normal play, exposed via Openplanet's `Fids::` **User** drive
(`Fids::GetUserFolder`). It walks that folder once and keyword-matches
`bronze`/`silver`/`gold`/`author`; a tier with no dedicated file falls back to
a shared `victory`/`record`/`podium`/`reward` cue. A tier with no match at all
is silent — no synthesised fallback. Use the window's **Medal splash → "Scan
game files for medal sounds"** button to see exactly what it found and
resolved per tier.

This isn't the game's install directory (`Fids::GetGameFolder`, the "Game"
drive) — that only reflects loose files literally shipped on disk, and
Turbo's title-pack audio is never unpacked there. It took walking all 5 Fids
drives in-game to find the real one; see `VfsSound.as`'s header comment for
the full investigation trail, including why a `Fids::GetGame(fullPath)`
single-file lookup and a compound-path `GetGameFolder` call both looked like
dead ends before the User drive was tried.

### Manual override

If auto-fetch ever picks the wrong file (or a fresh profile hasn't played
enough for the cache to be populated yet — untested how sparse it can be),
drop a file at one of these paths; `MedalSplash::SAMPLE_FILE` checks them
first and skips auto-fetch entirely when present:

| File                             | Tier   |
|-----------------------------------|--------|
| `assets/voice-medal-bronze.wav`  | Bronze |
| `assets/voice-medal-silver.wav`  | Silver |
| `assets/voice-medal-gold.wav`    | Gold   |
| `assets/voice-medal-author.wav`  | Author |

**These are gitignored (`/assets/*.wav`, `/assets/*.ogg`) and never
committed** — they're Nadeo's copyrighted audio. Only this README is tracked.
44.1 kHz mono 16-bit PCM WAV loads directly via `Audio::LoadSample` (`bext` /
`JUNK` ancillary chunks and all); `.ogg` works too. To swap the override
names/format, edit `MedalSplash::SAMPLE_FILE`. To pull the same files by hand
instead of relying on the cache, GbxPakExplorer
(<https://schadocalex.github.io/GbxPakExplorer/>) can browse
`TMTurbo.Title.Pack.Gbx → Media → Sounds → TMConsole → Voices` directly.

### Why the plugin can't just call the game's sound API

`CGameScriptHandlerPlaygroundInterface::PlayUiSound`,
`CAudioScriptManager::PlaySoundLibrary` / `PlaySoundEvent*`,
`CGameManiaplanetPlugin::PlaySound` are all ManiaScript-only (`"t":1`) — not
callable from an Openplanet plugin, so the plugin still can't *trigger* the
game's own ceremony (hence drawing its own banner in `MedalSplash.as`). Only
reading the raw audio *data* at runtime was ever in question, and that's what
`VfsSound.as` now does successfully via the User-drive cache.

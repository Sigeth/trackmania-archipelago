// Executes trap effects for items received from the multiworld.
//
// Like GameState.as and CampaignOverlay.as, this file touches engine nods (car
// scale, BackToMainMenu) -- so it must only run on the GAME THREAD, driven from
// Main.as's Update()/Render(). Never call into this from ApClient or the
// managers (those run on the client coroutine); ItemManager only *records*
// which traps arrived (ItemManager.PendingTraps) and Main.as drains that queue
// once per Update(), the same cross-thread hand-off GameState.pendingFinish
// uses.
//
// STATUS as of 2026-09-12 in-game testing -- only Blind Trap is confirmed
// working. The apworld's trap pool only selects Blind Trap until the rest are
// fixed (see Options.py / __init__.py ACTIVE_TRAP_NAMES); the other three stay
// wired up here (and reachable from the Window "Traps" debug buttons) purely
// so the next investigation has something to run against.
//
// Car-scale trap (giant / tiny car): CTrackManiaRace.ScaleCarValue is the same
// tuning field Turbo's own Bonus Mode uses for its mini-car/big-car power-ups
// (Openplanet.h ~19100, CTrackManiaRace). Reached via
// app.CurrentPlayground.Interface (CGamePlaygroundInterface) cast to
// CTrackManiaRaceInterface -> .Race. **CONFIRMED NOT WORKING** (2026-09-12) --
// the field writes and restores cleanly with no warning in the log, but the
// car did not visibly resize in-game.
//
// LEAD TRIED AND FALSIFIED (2026-09-12): turbo.openplanet.dev's class pages
// (built from a raw 2016 engine reflection dump) show CTrackManiaRaceRules
// ::EnableScaleCar and both CTrackManiaPlayer::TinyCar / CTmRaceRulesPlayer
// ::TinyCar as plain, non-const bools -- but that site does NOT reflect
// Openplanet's own read-only overlay on top of the engine. The real,
// authoritative source is the local dump Openplanet actually compiles
// against, `%USERPROFILE%\OpenplanetTurbo\OpenplanetTurbo.json` (grep for
// `"n":"<Member>"` -- a `"c":1` flag on the property means read-only, no
// setter). Checked there: EnableScaleCar has "c":1, and BOTH TinyCar
// occurrences (CTrackManiaPlayer and CTmRaceRulesPlayer) have "c":1. All
// three are read-only from script -- confirmed the hard way, by a live
// script compilation error ("The property has no set accessor") when this
// file briefly tried to write EnableScaleCar. None of them can be forced.
// Lesson: verify a member's writability against OpenplanetTurbo.json before
// coding against it, not just against turbo.openplanet.dev -- that site is
// good for discovering *what exists and its shape*, not for what Openplanet
// lets scripts mutate. CurrentRaceRules() is kept below for read-only
// diagnostic logging (is EnableScaleCar already on?) but no longer attempts
// to write it.
//
// Also ruled out this same pass (checked OpenplanetTurbo.json directly, not
// the docs site): CTrackManiaRace.BonusCarScale/BonusCarScaleAccel are BOTH
// "c":1 (read-only, despite showing as plain bools on turbo.openplanet.dev --
// that site's const-reporting is simply not reliable, confirmed twice now).
// CMotionTrackMobilScale.ScaleValue (found via the docs site's Scene/Motion
// class pages) IS genuinely writable per the JSON -- but no property or
// method anywhere in the whole dump returns/holds a CMotionTrackMobilScale
// handle (grepped the type string as a value, zero hits), and the one
// plausible path there (CGameMobil.SceneMobil -> CSceneMobil.MotionSolid) is
// statically typed CMotion@, a class from a completely separate hierarchy
// (parent CMwNod) than CMotionTrack/CMotionTrackMobilScale (parent
// CMwCmdContainer) -- an unrelated-hierarchy cast always yields null, so
// that path is a dead end, not just unverified.
//
// TRIED AND CONFIRMED NOT WORKING (2026-09-12, in-game, user confirmed no
// visible resize for either Giant or Tiny): CTrackManiaRace has two more
// scale-adjacent fields with no "c" flag -- `ScaleSpeedSec` (float) and
// `ScaleDuration` (uint) -- sitting right next to ScaleCarValue in the class
// (`ScaleFunc`, a CFuncKeysReal@ curve handle, is also unflagged/writable
// but was left alone -- constructing a valid keyframe curve from scratch is
// too speculative to guess at blind). Hypothesis was that the engine's
// mesh-scale interpolation only runs while a transition is "in progress"
// (ScaleDuration > 0), and past writes only ever set the instantaneous
// target with ScaleDuration left at its untouched default. StartCarScale()
// was changed to also set ScaleDuration (trap duration in ms) and
// ScaleSpeedSec (same duration in seconds) before ScaleCarValue, restoring
// all three on expiry -- confirmed via trace log that the pre-existing
// defaults (725 / 1) were read and overwritten correctly, and the target
// value (4 / 0.15) was set correctly, exactly as designed. **User confirmed
// live: still no visible effect, for either trap.** This specific lead is
// closed -- don't retry ScaleDuration/ScaleSpeedSec without new evidence.
//
// State of the investigation as of 2026-09-12: every writable, reachable
// field this investigation could find on CTrackManiaRace/CTrackManiaRaceRules
// that plausibly relates to car scale has now been tried or ruled out
// (ScaleCarValue alone: no effect. +ScaleDuration/ScaleSpeedSec: no effect.
// EnableScaleCar, BonusCarScale, BonusCarScaleAccel, both TinyCar members:
// all read-only, can't be forced. CMotionTrackMobilScale.ScaleValue: writable
// but structurally unreachable from any known accessor). No further
// script-side lead is currently known for making the car visibly resize.
// FOV WARP DIAGNOSTIC -- RESULT: CONFIRMED INERT (2026-09-12, in-game).
// CTrackManiaRace.FovY (confirmed writable via OpenplanetTurbo.json, no "c"
// flag) via the same CTrackManiaRaceInterface -> .Race accessor. Not a trap
// item -- no TRAP_NAMES entry, no apworld wiring, debug-button only
// (StartFovWarpDiagnostic()) -- purely to answer one question: can this
// accessor chain drive ANY visible effect outside real Bonus Mode? Trace log
// confirmed a huge, unmissable swing (`FovY 65 -> 162.5`, 2.5x) applied
// cleanly and restored cleanly twice. **User confirmed live both times:
// nothing visibly changed.** A field-of-view change that large would be
// impossible to miss if it were actually reaching the renderer, so this is
// strong evidence the whole `app.CurrentPlayground.Interface ->
// CTrackManiaRaceInterface -> .Race` accessor chain does not reach whatever
// object actually drives the rendered frame during solo campaign play --
// this was never just a car-scale-specific problem. Plausible explanation
// (untested): CTrackManiaRace is inherited by CTrackManiaRaceNew,
// CTrackManiaRace1P, and CTrackManiaRaceNet (per turbo.openplanet.dev); solo
// campaign racing may run through one of those subclasses with its own
// separate render/state path that doesn't consult the base class's fields
// the way Bonus Mode's own code does, or `pg.Interface` may simply resolve
// to a different/inactive object than whatever the renderer actually reads
// each frame. **Conclusion: this whole accessor chain should not be trusted
// to drive visual effects going forward without first sanity-checking that
// it reflects live state** (e.g. does a field like `LapCount` actually
// change as the player completes laps?) before writing any more code against
// it. No further engine-nod-based visual-effect trap idea is currently
// planned via this chain.
//
// GITHUB SEARCH (2026-09-14): searched for any real Openplanet plugin that
// implements a working car-resize effect, per the "check real plugins when
// stuck" rule. Zero hits for any Openplanet AngelScript plugin doing this.
// The only real code that flips `EnableScaleCar`/drives the mini-car/big-car
// mechanic is Nadeo's/community **ManiaScript mode scripts** (server-side
// `.Script.txt`, e.g. Plambt/TM-SMScripts's `KEKLRounds.Script.txt`,
// `Rounds-Chaos.Script.txt`, BigBang1112/nadeo-envimix's
// `EnvimixTimeAttack.Script.txt`) -- a completely different, server-
// authoritative scripting environment (the mode script that defines and
// runs the match) with no relationship to Openplanet's client-side
// AngelScript plugin API. Those scripts only ever set the `EnableScaleCar`/
// `EnableBonusEvents` flags; the actual scale-application logic lives inside
// Nadeo's own built-in base mode scripts (`Modes/TrackMania/Rounds.Script.txt`
// etc., shipped inside the game, not in any of these repos) and is driven by
// that mode's own bonus-car-spawn event system -- not a per-frame property a
// plugin could piggyback on for an already-running solo campaign race. One
// real Openplanet plugin found reading `CTrackManiaRaceRules.EnableScaleCar`
// at all -- kalleruud/tm-webhooks-plugin's `TurboGameAdapter.as` -- only
// *reads* it (to report round type in a webhook payload), never writes it,
// consistent with our own `"c":1` read-only finding. **This closes the
// Giant/Tiny Car investigation with outside confirmation: not just "we
// couldn't make it work," but "the mechanism this trap wanted doesn't exist
// in any form Openplanet plugins can reach at all" -- it's architecturally a
// mode-script feature, not a client-plugin one.
//
// FOLLOW-UP CHECKED AND CLOSED (2026-09-14): swapping the active mode script
// to one that already implements car-scale (e.g. KEKLRounds.Script.txt)
// instead of forcing fields on the campaign's own script. openplanet-nl/
// turbo-scripts -- the Openplanet team's own repo dumping Turbo's original
// .Script.txt files -- states in its README that running a custom menu/mode
// script requires a patched game. Mode-script loading/swapping is gated
// behind modifying the game binary, outside what an Openplanet AngelScript
// plugin (sandboxed, unmodified exe) can do. The writable mode-script fields
// found in OpenplanetTurbo.json (CTrackManiaNetworkServerInfo.
// NextScriptRelName / NextGameMode_Script) are dedicated-server host config,
// never consulted by offline solo campaign; CGameCtnChallengeGroup.
// ModeScriptName is static campaign metadata, not a live switch. No
// script-swap workaround exists for any future trap idea either.**
//
// Blind trap: a full-screen black nvg rect for S_BlindDurationSec, drawn from
// Main.as's Render() -- the exact technique MedalSplash.as already uses. No
// engine nod involved. **CONFIRMED WORKING** in-game 2026-09-12.
//
// Respawn trap: CTrackMania.BackToMainMenu(), the same call GameState.as
// already uses (confirmed in-game, in that lock-enforcement context) to
// bounce the player out of a locked track. Reused here for its practical
// "abandon this run" effect. **Marked not working as a trap** per user
// feedback 2026-09-12 -- both "respawn is not what I wanted" (wrong effect)
// and a later "mark everything else not working" pass. Turbo exposes no
// in-place restart or checkpoint-respawn call from script (see the workspace
// CLAUDE.md open questions for why a real respawn isn't possible). Candidates
// for next time (see [[traps-implemented]] memory): try
// CTrackManiaMenus.DialogQuitRace_OnRestartMap() for a real in-place restart
// (untested), drop the trap entirely, or keep this effect under a less
// misleading name (e.g. "DNF Trap") if it's ever confirmed to behave.

namespace TrapManager {
    // ---- Blind ----------------------------------------------------------
    uint64 m_blindStartMs = 0;
    uint64 m_blindUntilMs = 0;

    // ---- Car scale (giant / tiny) ---------------------------------------
    bool m_carScaleActive = false;
    float m_carScaleDefault = 1.0f;
    uint m_scaleDurationDefault = 0;
    float m_scaleSpeedSecDefault = 0.0f;
    uint64 m_carScaleUntilMs = 0;

    // ---- FOV warp (diagnostic only, not a trap item) ---------------------
    bool m_fovWarpActive = false;
    float m_fovDefault = 1.0f;
    uint64 m_fovWarpUntilMs = 0;

    // Dispatch one trap item by name. Game-thread only.
    void Trigger(const string &in itemName) {
        if (itemName == TRAP_BLIND) StartBlind();
        else if (itemName == TRAP_GIANT_CAR) StartCarScale(S_GiantCarScale);
        else if (itemName == TRAP_TINY_CAR) StartCarScale(S_TinyCarScale);
        else if (itemName == TRAP_RESPAWN) DoRespawn();
        else Log::Warn("TrapManager: unknown trap item '" + itemName + "'");
    }

    // Call once per game-thread Update() to expire timed effects.
    void Update() {
        if (m_carScaleActive && Time::Now >= m_carScaleUntilMs) {
            auto race = CurrentRace();
            if (race !is null) {
                race.ScaleCarValue = m_carScaleDefault;
                race.ScaleDuration = m_scaleDurationDefault;
                race.ScaleSpeedSec = m_scaleSpeedSecDefault;
            }
            m_carScaleActive = false;
            Log::Trace("Trap: car scale restored to " + m_carScaleDefault
                       + " (ScaleDuration -> " + m_scaleDurationDefault
                       + ", ScaleSpeedSec -> " + m_scaleSpeedSecDefault + ")");
        }
        if (m_fovWarpActive && Time::Now >= m_fovWarpUntilMs) {
            auto race = CurrentRace();
            if (race !is null) race.FovY = m_fovDefault;
            m_fovWarpActive = false;
            Log::Trace("Diagnostic: FovY restored to " + m_fovDefault);
        }
    }

    // ---- Blind ------------------------------------------------------------

    void StartBlind() {
        m_blindStartMs = Time::Now;
        m_blindUntilMs = Time::Now + uint64(S_BlindDurationSec * 1000.0f);
        Log::Info("Trap: Blind for " + S_BlindDurationSec + "s");
        Toast("Trap: blind for " + int(S_BlindDurationSec) + "s");
    }

    bool IsBlindActive() { return Time::Now < m_blindUntilMs; }

    // Draws the full-screen black overlay. Called from the plugin's Render().
    void RenderBlind() {
        if (!IsBlindActive()) return;
        auto dl = UI::GetForegroundDrawList();
        if (dl is null) return;

        float sw = float(Display::GetWidth());
        float sh = float(Display::GetHeight());

        float t = float(Time::Now - m_blindStartMs) / 1000.0f;
        float fade = 0.35f;
        float a = 1.0f;
        if (t < fade) a = t / fade;
        else if (t > S_BlindDurationSec - fade) a = (S_BlindDurationSec - t) / fade;
        a = Math::Clamp(a, 0.0f, 1.0f);

        dl.AddRectFilled(vec4(0.0f, 0.0f, sw, sh), vec4(0.0f, 0.0f, 0.0f, a));
    }

    // ---- Car scale (giant / tiny) -----------------------------------------

    void StartCarScale(float scale) {
        auto race = CurrentRace();
        if (race is null) {
            Log::Warn("Trap: car-scale skipped -- no live CTrackManiaRace"
                      + " (not in a race, or the accessor needs updating)");
            return;
        }
        // EnableScaleCar is READ-ONLY on this build (OpenplanetTurbo.json marks
        // it "c":1 -- confirmed by a script compilation error when this used to
        // write it: "The property has no set accessor"). Can't force it on;
        // only log its state for diagnosis.
        auto rules = CurrentRaceRules();
        if (rules !is null) {
            Log::Trace("Trap: car-scale -- CTrackManiaRaceRules.EnableScaleCar = "
                       + rules.EnableScaleCar + " (read-only, cannot be forced)");
        } else {
            Log::Warn("Trap: car-scale -- no CTrackManiaRaceRules, cannot read EnableScaleCar");
        }
        if (!m_carScaleActive) {
            m_carScaleDefault = race.ScaleCarValue;
            m_scaleDurationDefault = race.ScaleDuration;
            m_scaleSpeedSecDefault = race.ScaleSpeedSec;
        }
        // Set up the transition window before committing the target value --
        // see the EXPERIMENT note above. Units are a guess: ScaleDuration as
        // the trap duration in ms, ScaleSpeedSec as the same duration in
        // seconds (a "how long the transition takes" reading, not confirmed).
        uint durationMs = uint(S_TrapDurationSec * 1000.0f);
        race.ScaleDuration = durationMs;
        race.ScaleSpeedSec = S_TrapDurationSec;
        race.ScaleCarValue = scale;
        m_carScaleActive = true;
        m_carScaleUntilMs = Time::Now + uint64(S_TrapDurationSec * 1000.0f);
        Log::Info("Trap: car scale -> " + scale + " for " + S_TrapDurationSec + "s"
                  + " (ScaleDuration " + m_scaleDurationDefault + " -> " + durationMs
                  + ", ScaleSpeedSec " + m_scaleSpeedSecDefault + " -> " + S_TrapDurationSec + ")");
        Toast("Trap: " + (scale > 1.0f ? "giant" : "tiny") + " car for "
              + int(S_TrapDurationSec) + "s");
    }

    // ---- FOV warp (diagnostic only) ----------------------------------------

    // Multiplies the live FovY for S_TrapDurationSec, then restores it.
    // Relative (not an absolute target) since FovY's units/range are
    // undocumented anywhere found -- multiplying whatever it currently reads
    // sidesteps guessing units. Debug-button only; not a trap item.
    void StartFovWarpDiagnostic() {
        auto race = CurrentRace();
        if (race is null) {
            Log::Warn("Diagnostic: FOV warp skipped -- no live CTrackManiaRace");
            return;
        }
        if (!m_fovWarpActive) m_fovDefault = race.FovY;
        float warped = m_fovDefault * 2.5f;
        race.FovY = warped;
        m_fovWarpActive = true;
        m_fovWarpUntilMs = Time::Now + uint64(S_TrapDurationSec * 1000.0f);
        Log::Info("Diagnostic: FovY " + m_fovDefault + " -> " + warped
                  + " for " + S_TrapDurationSec + "s");
        Toast("Diagnostic: FOV warp for " + int(S_TrapDurationSec) + "s");
    }

    // app.CurrentPlayground.Interface -> CTrackManiaRaceInterface.Race. Returns
    // null (never throws) when any link of that chain isn't what we expect.
    CTrackManiaRace@ CurrentRace() {
        auto app = cast<CGameCtnApp>(GetApp());
        if (app is null) return null;
        auto pg = app.CurrentPlayground;
        if (pg is null) return null;
        auto iface = cast<CTrackManiaRaceInterface>(pg.Interface);
        if (iface is null) return null;
        return iface.Race;
    }

    // app.PlaygroundScript cast to CTrackManiaRaceRules -- holds EnableScaleCar
    // and the per-player CTmRaceRulesPlayer nods. Returns null outside a race.
    CTrackManiaRaceRules@ CurrentRaceRules() {
        auto app = cast<CGameCtnApp>(GetApp());
        if (app is null) return null;
        return cast<CTrackManiaRaceRules>(app.PlaygroundScript);
    }

    // ---- Respawn (abandon run) ----------------------------------------------

    void DoRespawn() {
        auto mp = cast<CTrackMania>(GetApp());
        if (mp is null) return;
        Log::Info("Trap: respawn -- returning to menu");
        Toast("Trap: run abandoned");
        mp.BackToMainMenu();
    }

    // ---- shared -------------------------------------------------------------

    void Toast(const string &in text) {
        if (!S_Notifications) return;
        UI::ShowNotification("Archipelago", text, vec4(0.6f, 0.15f, 0.15f, 1.0f), 3000);
    }
}
